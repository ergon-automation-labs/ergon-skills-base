defmodule BotArmySkills.SkillRunner do
  @moduledoc """
  Executes a DB-driven skill: renders the template, submits to LLM, executes actions.

  The flow:
  1. Build template variables from payload, context, soul, and tenant_id
  2. Render the markdown template via TemplateRenderer
  3. Submit the rendered prompt to the LLM
  4. Execute any {{action:slug}} references found in the template
  5. Publish completion events
  """

  require Logger

  alias BotArmySkills.{SkillDefinition, TemplateRenderer, ActionExecutor}

  @llm_subject "llm.skill.prompt.submit"
  @default_llm_request_timeout_ms 15_000
  @llm_request_retries 1
  @llm_retry_backoff_ms 250

  @doc "Execute a DB-driven skill."
  @spec execute(SkillDefinition.t(), map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute(%SkillDefinition{} = skill, payload, ctx, opts \\ []) do
    case BotArmySkills.SkillExecutor.lookup(skill.slug) do
      nil -> execute_llm_driven_skill(skill, payload, ctx, opts)
      executor -> executor.execute(skill, payload, opts)
    end
  end

  defp execute_llm_driven_skill(skill, payload, ctx, opts) do
    tenant_id = skill.tenant_id
    repo = Keyword.get(opts, :repo, BotArmyRuntime.Ecto.Repo)

    # Load soul if available in context
    soul_config = load_soul_config(ctx)

    # Build template variables
    vars = %{
      payload: payload,
      context: Map.get(ctx, :context, %{}),
      soul: soul_config,
      tenant_id: tenant_id,
      repo: repo
    }

    # Render template
    rendered_prompt = TemplateRenderer.render(skill.markdown_content, vars)

    # Determine LLM hint
    hint = skill.llm_hint || :none

    # Submit to LLM via NATS request/reply
    case submit_to_llm(rendered_prompt, hint) do
      {:ok, completion} ->
        action_payload = build_action_payload(payload, completion)

        action_results =
          ActionExecutor.execute_actions_in_template(
            tenant_id,
            skill.markdown_content,
            action_payload,
            repo: repo
          )

        # Publish skill completed event
        publish_skill_completed(skill, completion, action_results)

        {:ok,
         %{
           skill: skill.name,
           slug: skill.slug,
           completion: completion,
           actions: action_results
         }}

      {:error, reason} ->
        Logger.error("[SkillRunner] LLM request failed for skill #{skill.slug}",
          slug: skill.slug,
          reason: inspect(reason)
        )

        publish_skill_failed(skill, reason)

        {:error, {:llm_error, reason}}
    end
  end

  defp load_soul_config(ctx) do
    case Map.get(ctx, :soul) do
      nil ->
        # Try to load soul from BotArmy.Soul if available
        bot_id = Map.get(ctx, :bot_id)
        tenant_id = Map.get(ctx, :tenant_id, BotArmyRuntime.Tenant.default_tenant_id())

        try do
          case BotArmy.Soul.get(bot_id, tenant_id: tenant_id) do
            nil -> %{}
            soul -> soul.config || %{}
          end
        rescue
          _ -> %{}
        end

      soul when is_map(soul) ->
        Map.get(soul, :config, soul)
    end
  end

  defp submit_to_llm(prompt, hint) do
    prompt_id = UUID.uuid4()
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    envelope = %{
      "event_id" => UUID.uuid4(),
      "event" => @llm_subject,
      "schema_version" => "1.0",
      "timestamp" => timestamp,
      "source" => "skills_bot",
      "source_node" => node() |> Atom.to_string(),
      "triggered_by" => "skills_runner",
      "payload" => %{
        "prompt_id" => prompt_id,
        "text" => prompt,
        "context" => "skill_hint=#{hint}",
        "model" => "auto"
      }
    }

    with {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000),
         {:ok, json} <- Jason.encode(envelope) do
      request_llm_with_retry(conn, json, hint, String.length(prompt), prompt_id, 0)
    else
      {:error, reason} -> {:error, {:llm_connection_or_encode_failed, reason}}
    end
  end

  defp request_llm_with_retry(conn, json, hint, prompt_length, prompt_id, attempt) do
    started_at = System.monotonic_time(:millisecond)

    case Gnat.request(conn, @llm_subject, json, timeout: llm_request_timeout_ms()) do
      {:ok, %{body: response_body}} ->
        latency_ms = System.monotonic_time(:millisecond) - started_at
        decode_llm_response(response_body, hint, prompt_length, prompt_id, attempt, latency_ms)

      {:error, :timeout} when attempt < @llm_request_retries ->
        Logger.warning(
          "[SkillRunner] LLM request timeout, retrying",
          subject: @llm_subject,
          attempt: attempt + 1,
          max_retries: @llm_request_retries,
          timeout_ms: llm_request_timeout_ms(),
          retry_backoff_ms: @llm_retry_backoff_ms,
          prompt_length: prompt_length,
          prompt_id: prompt_id,
          hint: hint
        )

        Process.sleep(@llm_retry_backoff_ms * (attempt + 1))
        request_llm_with_retry(conn, json, hint, prompt_length, prompt_id, attempt + 1)

      {:error, reason} ->
        latency_ms = System.monotonic_time(:millisecond) - started_at

        Logger.error(
          "[SkillRunner] LLM request failed",
          subject: @llm_subject,
          attempt: attempt + 1,
          timeout_ms: llm_request_timeout_ms(),
          prompt_length: prompt_length,
          prompt_id: prompt_id,
          hint: hint,
          latency_ms: latency_ms,
          reason: inspect(reason)
        )

        {:error, {:llm_request_failed, reason}}
    end
  end

  defp decode_llm_response(response_body, hint, prompt_length, prompt_id, attempt, latency_ms) do
    case Jason.decode(response_body) do
      {:ok, response} ->
        completion =
          get_in(response, ["payload", "completion"]) ||
            Map.get(response, "completion") ||
            Map.get(response, "content")

        if is_binary(completion) and completion != "" do
          Logger.info(
            "[SkillRunner] LLM request succeeded",
            subject: @llm_subject,
            attempt: attempt + 1,
            timeout_ms: llm_request_timeout_ms(),
            prompt_length: prompt_length,
            prompt_id: prompt_id,
            completion_length: String.length(completion),
            hint: hint,
            latency_ms: latency_ms
          )

          {:ok, completion}
        else
          response_error =
            Map.get(response, "error") ||
              get_in(response, ["payload", "error"]) ||
              get_in(response, ["payload", "reason"])

          Logger.error(
            "[SkillRunner] LLM response missing completion",
            subject: @llm_subject,
            attempt: attempt + 1,
            timeout_ms: llm_request_timeout_ms(),
            prompt_length: prompt_length,
            prompt_id: prompt_id,
            hint: hint,
            latency_ms: latency_ms,
            response_keys: Map.keys(response),
            response_error: inspect(response_error)
          )

          case response_error do
            nil ->
              {:error, {:llm_missing_completion, Map.keys(response)}}

            error ->
              {:error, {:llm_error_response, error}}
          end
        end

      {:error, reason} ->
        Logger.error(
          "[SkillRunner] LLM response decode failed",
          subject: @llm_subject,
          attempt: attempt + 1,
          timeout_ms: llm_request_timeout_ms(),
          prompt_length: prompt_length,
          prompt_id: prompt_id,
          hint: hint,
          latency_ms: latency_ms,
          reason: inspect(reason)
        )

        {:error, {:llm_response_decode_failed, reason}}
    end
  end

  @doc false
  def build_action_payload_for_test(payload, completion),
    do: build_action_payload(payload, completion)

  defp build_action_payload(payload, completion) when is_binary(completion) do
    payload
    |> Map.put("skill_completion", completion)
    |> maybe_fill_podcast_write(completion)
  end

  defp maybe_fill_podcast_write(payload, completion) do
    if persist_podcast?(payload) do
      case Map.get(payload, "podcast_write") do
        %{"content" => content} when is_binary(content) and content != "" ->
          payload

        podcast_write when is_map(podcast_write) ->
          Map.put(
            payload,
            "podcast_write",
            podcast_write_payload(podcast_write, completion, payload)
          )

        _ ->
          Map.put(payload, "podcast_write", podcast_write_payload(%{}, completion, payload))
      end
    else
      payload
    end
  end

  defp persist_podcast?(payload) do
    Map.get(payload, "persist_podcast") in [true, "true", 1, "1"]
  end

  defp podcast_write_payload(podcast_write, completion, payload) do
    podcast_write
    |> Map.put("schema_version", "1.0")
    |> Map.put_new("mode", "write")
    |> Map.put("content", completion)
    |> Map.put_new("relative_path", default_podcast_relative_path(payload))
  end

  defp default_podcast_relative_path(payload) do
    stamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    slug = Map.get(payload, "episode_slug", "daily-learning")
    "resources/learning_podcasts/inbox/#{stamp}_#{slug}.md"
  end

  defp publish_skill_completed(skill, completion, action_results) do
    BotArmyCore.NATS.publish("bot.army.#{skill.name}.event.skill_completed", %{
      "skill" => Atom.to_string(skill.name),
      "slug" => skill.slug,
      "tenant_id" => skill.tenant_id,
      "completion_length" => String.length(completion),
      "actions_executed" =>
        Enum.map(action_results, fn {slug, result} ->
          %{slug: slug, success: match?({:ok, _}, result)}
        end),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
  rescue
    _ -> :ok
  end

  defp publish_skill_failed(skill, reason) do
    BotArmyCore.NATS.publish("bot.army.#{skill.name}.event.skill_failed", %{
      "skill" => Atom.to_string(skill.name),
      "slug" => skill.slug,
      "tenant_id" => skill.tenant_id,
      "reason" => inspect(reason),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
  rescue
    _ -> :ok
  end

  defp llm_request_timeout_ms do
    Application.get_env(
      :bot_army_skills,
      :llm_request_timeout_ms,
      @default_llm_request_timeout_ms
    )
  end
end
