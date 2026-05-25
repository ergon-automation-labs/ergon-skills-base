defmodule BotArmySkills.Actions.NatsRequest do
  @moduledoc """
  NATS request/reply action handler.

  Config:
    - `subject` (required unless using `subject_key`) — target subject
    - `subject_key` (optional) — payload key containing dynamic target subject
    - `payload_key` (optional) — payload key containing the request body
    - `allowed_subject_prefixes` (optional) — list of allowed subject prefixes
    - `validate_bridge_schema` (optional) — validate bridge request body shape (default: false)
    - `forward_response_subject` (optional) — subject to forward gathered response context (for example `synapse.analyze`)
    - `forward_response_max_chars` (optional) — max chars for forwarded response summary text (default: 4000)
    - `forward_mode` (optional) — `full` (include full response) or `summary_only` (default)
    - `forward_detail_override_key` (optional) — input payload flag that requests full forwarding (default: `detail_requested`)
    - `timeout_ms` (optional) — request timeout in milliseconds (default: 15_000)
    - `envelope` (optional) — whether to wrap payload in a standard envelope (default: true)
  """

  @behaviour BotArmySkills.ActionHandler
  @default_timeout_ms 15_000
  @default_forward_max_chars 4000
  @default_forward_mode "summary_only"
  @default_forward_detail_override_key "detail_requested"

  @impl true
  def execute(config, payload) do
    with {:ok, subject} <- resolve_subject(config, payload),
         {:ok, request_payload} <- resolve_request_payload(config, payload),
         :ok <- validate_subject(subject, config),
         :ok <- validate_request_payload(subject, request_payload, config),
         {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000),
         {:ok, json} <- Jason.encode(build_message(subject, request_payload, config)),
         {:ok, reply} <- Gnat.request(conn, subject, json, timeout: timeout_ms(config)),
         {:ok, decoded} <- Jason.decode(reply.body) do
      forward_result =
        maybe_forward_response_to_subject(config, payload, subject, request_payload, decoded)

      result = %{
        subject: subject,
        replied: true,
        response: decoded
      }

      case forward_result do
        :not_configured ->
          {:ok, result}

        {:ok, forward_subject} ->
          {:ok, Map.put(result, :forwarded_to_subject, forward_subject)}

        {:error, reason} ->
          {:ok, Map.put(result, :forwarding_error, reason)}
      end
    else
      {:error, reason} -> {:error, {:nats_request_failed, reason}}
    end
  end

  defp build_message(subject, payload, config) do
    if Map.get(config, "envelope", true) do
      %{
        "event" => subject,
        "event_id" => UUID.uuid4(),
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "source" => "bot_army_skills",
        "schema_version" => "1.0",
        "payload" => payload
      }
    else
      payload
    end
  end

  defp resolve_request_payload(config, payload) do
    case Map.get(config, "payload_key") do
      key when is_binary(key) and key != "" ->
        case Map.get(payload, key) do
          request_payload when is_map(request_payload) -> {:ok, request_payload}
          _ -> {:error, {:invalid_or_missing_payload, key}}
        end

      _ ->
        if is_map(payload), do: {:ok, payload}, else: {:error, :invalid_payload}
    end
  end

  defp timeout_ms(config) do
    case Map.get(config, "timeout_ms", @default_timeout_ms) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_timeout_ms
    end
  end

  defp resolve_subject(config, payload) do
    subject_key = Map.get(config, "subject_key")

    if is_binary(subject_key) and subject_key != "" do
      case Map.get(payload, subject_key) do
        subject when is_binary(subject) and subject != "" -> {:ok, subject}
        _ -> {:error, {:invalid_or_missing_subject, subject_key}}
      end
    else
      case Map.get(config, "subject") do
        subject when is_binary(subject) and subject != "" -> {:ok, subject}
        _ -> {:error, :missing_subject_config}
      end
    end
  end

  defp validate_subject(subject, config) do
    case Map.get(config, "allowed_subject_prefixes", []) do
      [] ->
        :ok

      prefixes when is_list(prefixes) ->
        if Enum.any?(prefixes, &String.starts_with?(subject, &1)) do
          :ok
        else
          {:error, {:subject_not_allowed, subject}}
        end

      _ ->
        {:error, :invalid_allowed_subject_prefixes}
    end
  end

  defp validate_request_payload(subject, request_payload, config) do
    if Map.get(config, "validate_bridge_schema", false) do
      BotArmySkills.BridgeRequestValidator.validate(subject, request_payload)
    else
      :ok
    end
  end

  defp maybe_forward_response_to_subject(
         config,
         input_payload,
         bridge_subject,
         request_payload,
         response
       ) do
    case Map.get(config, "forward_response_subject") do
      forward_subject when is_binary(forward_subject) and forward_subject != "" ->
        payload =
          build_forward_payload(config, input_payload, bridge_subject, request_payload, response)

        case BotArmyCore.NATS.publish(forward_subject, payload) do
          {:ok, _} -> {:ok, forward_subject}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :not_configured
    end
  end

  defp build_forward_payload(config, input_payload, bridge_subject, request_payload, response) do
    question =
      "Bridge response received for #{bridge_subject}. Decide next action and whether pi-go should be triggered."

    context = %{
      "requester" => Map.get(input_payload, "requester"),
      "intent" => Map.get(input_payload, "intent"),
      "capability" => Map.get(input_payload, "capability"),
      "bridge_subject" => bridge_subject,
      "bridge_request" => request_payload,
      "bridge_response_summary" => summarize_response(response, config)
    }

    effective_mode = effective_forward_mode(config, input_payload)

    context =
      if effective_mode == "full" do
        Map.put(context, "bridge_response", response)
      else
        context
      end

    %{
      "question" => question,
      "needs_more_context_contract" => %{
        "can_request_more_context" => true,
        "detail_override_key" => detail_override_key(config),
        "rerun_guidance" =>
          "When context is insufficient, re-run the same bridge subject with detail override enabled."
      },
      "context" => context
    }
  end

  defp summarize_response(response, config) do
    max_chars =
      case Map.get(config, "forward_response_max_chars", @default_forward_max_chars) do
        value when is_integer(value) and value > 0 -> value
        _ -> @default_forward_max_chars
      end

    summary =
      case Jason.encode(response) do
        {:ok, json} -> json
        _ -> inspect(response)
      end

    if String.length(summary) > max_chars do
      String.slice(summary, 0, max_chars) <> "...[truncated]"
    else
      summary
    end
  end

  defp forward_mode(config) do
    case Map.get(config, "forward_mode", @default_forward_mode) do
      "full" -> "full"
      "summary_only" -> "summary_only"
      _ -> @default_forward_mode
    end
  end

  defp detail_override_key(config) do
    case Map.get(config, "forward_detail_override_key", @default_forward_detail_override_key) do
      key when is_binary(key) and key != "" -> key
      _ -> @default_forward_detail_override_key
    end
  end

  defp effective_forward_mode(config, input_payload) do
    if Map.get(input_payload, detail_override_key(config), false) == true do
      "full"
    else
      forward_mode(config)
    end
  end
end
