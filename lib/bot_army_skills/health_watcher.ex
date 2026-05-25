defmodule BotArmySkills.HealthWatcher do
  @moduledoc """
  Watches system.health heartbeats and auto-generates incident reports
  when a bot reports degraded or unhealthy status.

  Deduplicates: one incident report per service per hour.
  """
  use GenServer
  require Logger

  alias BotArmyRuntime.NATS.Connection

  @reconnect_delay_ms 5_000
  @incident_cooldown_seconds 3_600
  @health_subject "system.health"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscription: nil, last_incident: %{}, connected: false}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case Process.whereis(Connection) do
      nil ->
        Logger.warning("[HealthWatcher] NATS connection not ready, retrying...")
        Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
        {:noreply, state}

      _ ->
        case GenServer.call(Connection, :get_connection, 5_000) do
          {:ok, conn} ->
            case Gnat.sub(conn, self(), @health_subject) do
              {:ok, sub} ->
                Logger.info("[HealthWatcher] Subscribed to #{@health_subject}")
                {:noreply, %{state | subscription: sub, connected: true}}

              {:error, reason} ->
                Logger.error("[HealthWatcher] Failed to subscribe: #{inspect(reason)}")
                Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
                {:noreply, state}
            end

          {:error, _reason} ->
            Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:connect_retry, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    case Jason.decode(msg.body) do
      {:ok, envelope} ->
        handle_health_envelope(envelope, state)

      {:error, reason} ->
        Logger.warning("[HealthWatcher] Failed to decode health message: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("[HealthWatcher] NATS disconnected, will reconnect")
    {:noreply, %{state | connected: false, subscription: nil}, {:continue, :connect}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("[HealthWatcher] NATS reconnected")
    {:noreply, state, {:continue, :connect}}
  end

  defp handle_health_envelope(%{"payload" => payload} = envelope, state) do
    status = payload["status"] || "unknown"
    service = payload["service"] || envelope["source"] || "unknown"

    if status in ["degraded", "unhealthy", "critical", "error"] do
      now = System.monotonic_time(:second)
      last = Map.get(state.last_incident, service, 0)

      if now - last > @incident_cooldown_seconds do
        Logger.info("[HealthWatcher] #{service} is #{status} — triggering incident report")

        Task.start(fn ->
          handler = Application.get_env(:bot_army_skills, :incident_report_handler)

          if handler do
            result = handler.handle_generate(%{"bot_name" => service})

            if result["ok"] do
              Logger.info(
                "[HealthWatcher] Incident report generated for #{service}: #{result["data"]["relative_path"]}"
              )
            else
              Logger.error(
                "[HealthWatcher] Incident report failed for #{service}: #{result["error"]}"
              )
            end
          else
            Logger.debug("[HealthWatcher] No incident report handler configured for #{service}")
          end
        end)

        {:noreply, %{state | last_incident: Map.put(state.last_incident, service, now)}}
      else
        remaining = @incident_cooldown_seconds - (now - last)

        Logger.debug(
          "[HealthWatcher] #{service} still #{status}, cooldown #{remaining}s remaining"
        )

        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp handle_health_envelope(_envelope, state) do
    {:noreply, state}
  end
end
