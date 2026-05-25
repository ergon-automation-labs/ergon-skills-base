defmodule BotArmySkills.NATS.Consumer do
  @moduledoc """
  NATS consumer for skill invocation commands.

  Subscribes to `bot.army.skills.command.>` and routes skill execution requests.
  Any bot can publish to `bot.army.skills.command.<slug>` to invoke a skill.

  Handlers are discovered from application config (`:bot_army_skills, :handlers`)
  and implement the `BotArmySkills.Handler` behaviour. Add custom handlers by
  appending to the config list — no consumer edits required.

  ## Flow

  1. Bot publishes to `bot.army.skills.command.summarize` with payload
  2. Consumer extracts slug from subject suffix
  3. Loads skill definition from SkillCache
  4. SkillRunner.execute(skill, payload, context)
  5. If msg.reply_to is set, reply with completion (synchronous path)
  6. Publish completion event (asynchronous path)
  """

  use GenServer
  require Logger

  alias BotArmyRuntime.NATS.Connection
  alias BotArmyRuntime.Registry
  alias BotArmyCore.NATS.Decoder

  @reconnect_delay_ms 5_000
  @version Mix.Project.config()[:version]
  @registry_heartbeat_ms 20_000
  @skills_command_prefix "bot.army.skills.command."
  @legacy_command_prefix "bot.army.command."
  @skills_command_subject "#{@skills_command_prefix}>"
  @legacy_command_subject "#{@legacy_command_prefix}>"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("[SkillsConsumer] Starting skills command consumer")

    {subject_specs, dispatch_map} = build_handler_registry()

    core_subjects = [
      %{
        subject: @skills_command_subject,
        type: :subscribe,
        description: "Skill invocation commands"
      },
      %{
        subject: @legacy_command_subject,
        type: :subscribe,
        description: "Legacy skill invocation commands"
      },
      %{
        subject: "gossip.poll.broadcast",
        type: :subscribe,
        description: "Army general poll broadcasts"
      }
    ]

    all_subjects = core_subjects ++ subject_specs
    content_subjects = MapSet.new(subject_specs, & &1.subject)

    state = %{
      subscriptions: [],
      opts: opts,
      all_subjects: all_subjects,
      content_subjects: content_subjects,
      dispatch_map: dispatch_map
    }

    {:ok, state, {:continue, :connect}}
  end

  defp build_handler_registry do
    handlers = Application.get_env(:bot_army_skills, :handlers, [])

    Enum.reduce(handlers, {[], %{}}, fn mod, {specs, dispatch} ->
      mod_subjects = mod.subjects()
      new_dispatch = Map.new(mod_subjects, &{&1.subject, mod})
      {specs ++ mod_subjects, Map.merge(dispatch, new_dispatch)}
    end)
  end

  @impl true
  def handle_continue(:connect, state) do
    case Process.whereis(Connection) do
      nil ->
        Logger.warning("[SkillsConsumer] NATS connection process not started yet")
        handle_connection_unavailable(state)

      _ ->
        case GenServer.call(Connection, :get_connection, 5_000) do
          {:ok, conn} ->
            Connection.subscribe_to_status()
            subscribe_to_topics(conn, state)

          {:error, _reason} ->
            handle_connection_unavailable(state)
        end
    end
  end

  defp subscribe_to_topics(conn, state) do
    Logger.info("[SkillsConsumer] Connected to NATS, subscribing to skill commands")

    subscriptions =
      Enum.reduce_while(state.all_subjects, [], fn %{subject: subject}, acc ->
        case Gnat.sub(conn, self(), subject) do
          {:ok, sub} ->
            Logger.info("[SkillsConsumer] Subscribed to #{subject}")
            {:cont, [sub | acc]}

          {:error, reason} ->
            Logger.error("[SkillsConsumer] Failed to subscribe to #{subject}: #{inspect(reason)}")
            {:halt, {:error, reason}}
        end
      end)

    case subscriptions do
      {:error, _reason} ->
        Process.send_after(self(), :reconnect, @reconnect_delay_ms)
        {:noreply, state}

      subs when is_list(subs) ->
        Registry.register("skills", state.all_subjects, @version)
        Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
        {:noreply, %{state | subscriptions: subs}}
    end
  end

  defp handle_connection_unavailable(state) do
    Logger.warning("[SkillsConsumer] NATS connection not ready, will retry")
    Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:connect_retry, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("[SkillsConsumer] Attempting to reconnect to NATS")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      Logger.debug("[SkillsConsumer] Received message on subject: #{msg.topic}")

      cond do
        msg.topic == "gossip.poll.broadcast" ->
          case Jason.decode(msg.body) do
            {:ok, decoded} ->
              BotArmySkills.GossipPollVoter.handle_poll_broadcast(decoded)

            {:error, reason} ->
              Logger.warning("[SkillsConsumer] Failed to decode gossip poll: #{inspect(reason)}")
          end

        MapSet.member?(state.content_subjects, msg.topic) ->
          handle_content_request(msg, state.dispatch_map)

        true ->
          case Decoder.decode(msg.body) do
            {:ok, decoded} ->
              route_skill_command(decoded, msg, state)

            {:error, reason} ->
              Logger.warning(
                "[SkillsConsumer] Failed to decode message from #{msg.topic}: #{inspect(reason)}. " <>
                  "Publishers must send JSON matching Decoder (event_id, event, schema_version, timestamp, source, source_node, triggered_by, payload object)."
              )

              if msg.reply_to do
                reply_error(msg.reply_to, "Envelope decode failed: #{inspect(reason)}")
              end
          end
      end
    end)

    {:noreply, state}
  end

  defp handle_content_request(msg, dispatch_map) do
    query =
      case Jason.decode(msg.body) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    response =
      case Map.get(dispatch_map, msg.topic) do
        nil ->
          %{"ok" => false, "error" => "No handler for subject: #{msg.topic}"}

        handler_mod ->
          try do
            handler_mod.handle_message(msg.topic, query)
          rescue
            error ->
              Logger.error("[SkillsConsumer] Handler crash on #{msg.topic}: #{inspect(error)}")
              %{"ok" => false, "error" => "Handler error: #{inspect(error)}"}
          end
      end

    if msg.reply_to do
      reply_json(msg.reply_to, response)
    end
  end

  defp reply_json(reply_to, payload) do
    with {:ok, conn} <- GenServer.call(Connection, :get_connection, 5_000),
         {:ok, json} <- Jason.encode(payload) do
      :ok = Gnat.pub(conn, reply_to, json)
    else
      {:error, reason} ->
        Logger.error("[SkillsConsumer] Failed to publish content reply: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[SkillsConsumer] Disconnected from NATS, will reconnect")
    Process.send_after(self(), :reconnect, @reconnect_delay_ms)
    {:noreply, %{state | subscriptions: []}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("[SkillsConsumer] Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :connect}}
  end

  # Message routing

  defp route_skill_command(message, msg, state) do
    case message do
      %{"payload" => payload} = envelope ->
        execute_skill(msg.topic, envelope, payload, msg)
        state

      _ ->
        Logger.debug("[SkillsConsumer] Malformed skill command: #{inspect(message)}")

        if msg.reply_to do
          reply_error(msg.reply_to, "Malformed skill command envelope")
        end

        state
    end
  end

  defp execute_skill(subject, envelope, payload, msg) do
    slug =
      cond do
        String.starts_with?(subject, @skills_command_prefix) ->
          String.replace_prefix(subject, @skills_command_prefix, "")

        String.starts_with?(subject, @legacy_command_prefix) ->
          String.replace_prefix(subject, @legacy_command_prefix, "")

        true ->
          ""
      end

    if slug == "" do
      Logger.warning("[SkillsConsumer] Could not parse skill slug from subject: #{subject}")
      :ok
    else
      tenant_id = Map.get(envelope, "tenant_id", BotArmyRuntime.Tenant.default_tenant_id())

      Logger.debug(
        "[SkillsConsumer] Executing skill: #{slug} for tenant #{String.slice(tenant_id, 0, 8)}..."
      )

      case safe_get_skill(tenant_id, slug) do
        {:ok, nil} ->
          Logger.warning("[SkillsConsumer] Skill not found: #{slug}")

          if msg.reply_to do
            reply_error(msg.reply_to, "Skill not found: #{slug}")
          end

        {:ok, skill} ->
          ctx = %{
            source: Map.get(envelope, "source"),
            user_id: Map.get(envelope, "user_id"),
            tenant_id: tenant_id,
            event_id: Map.get(envelope, "event_id")
          }

          case BotArmySkills.SkillRunner.execute(skill, payload, ctx) do
            {:ok, result} ->
              completion = Map.get(result, :completion, "")

              if msg.reply_to do
                reply_success(msg.reply_to, completion)
              end

              publish_skill_executed(skill, result, envelope)

            {:error, reason} ->
              Logger.error("[SkillsConsumer] Skill execution failed: #{inspect(reason)}")

              if msg.reply_to do
                reply_error(msg.reply_to, "Skill execution failed: #{inspect(reason)}")
              end
          end

        {:error, reason} ->
          Logger.error("[SkillsConsumer] Skill lookup failed: #{inspect(reason)}")

          if msg.reply_to do
            reply_error(msg.reply_to, "Skill lookup failed: #{inspect(reason)}")
          end
      end
    end
  end

  defp safe_get_skill(tenant_id, slug) do
    case BotArmySkills.SkillCache.get_skill(tenant_id, slug) do
      {:error, reason} -> {:error, reason}
      skill -> {:ok, skill}
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp reply_success(reply_to, completion) do
    with {:ok, conn} <- GenServer.call(Connection, :get_connection, 5_000),
         {:ok, json} <-
           Jason.encode(%{
             "status" => "success",
             "payload" => %{"completion" => completion}
           }) do
      :ok = Gnat.pub(conn, reply_to, json)
    else
      {:error, reason} ->
        Logger.error("[SkillsConsumer] Failed to publish reply: #{inspect(reason)}")
    end
  end

  defp reply_error(reply_to, error) do
    with {:ok, conn} <- GenServer.call(Connection, :get_connection, 5_000),
         {:ok, json} <- Jason.encode(%{"status" => "error", "error" => error}) do
      :ok = Gnat.pub(conn, reply_to, json)
    else
      {:error, reason} ->
        Logger.error("[SkillsConsumer] Failed to publish error reply: #{inspect(reason)}")
    end
  end

  defp publish_skill_executed(skill, result, envelope) do
    BotArmyCore.NATS.publish("bot.army.command.executed", %{
      "skill" => Atom.to_string(skill.name),
      "slug" => skill.slug,
      "tenant_id" => skill.tenant_id,
      "completion_length" => String.length(Map.get(result, :completion, "")),
      "actions" => Map.get(result, :actions, []),
      "triggered_by" => Map.get(envelope, "source"),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
  rescue
    _ -> :ok
  end

  @impl true
  def handle_info(:registry_heartbeat, state) do
    if state.subscriptions != [] do
      Registry.register("skills", state.all_subjects, @version)
      BotArmySkills.GossipPollVoter.maybe_vote_on_heartbeat()
      Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    end

    {:noreply, state}
  end
end
