defmodule BotArmySkills.Handlers.DeskOperatorSnapshotHandler do
  @moduledoc """
  Deterministic desk assembly for operator reports.

  Probes live bridge and registry endpoints, returns structured JSON
  for downstream gazette / PARA / Discord consumers.
  """
  @behaviour BotArmySkills.Handler
  require Logger

  @max_retries 3
  @retry_delay_ms 1000

  @impl BotArmySkills.Handler
  def subjects do
    [
      %{
        subject: "bot.army.skills.desk_operator_snapshot.generate",
        type: :request_reply,
        description: "Generate deterministic desk snapshot from bridge and registry probes"
      }
    ]
  end

  @impl BotArmySkills.Handler
  def handle_message("bot.army.skills.desk_operator_snapshot.generate", query),
    do: handle_generate(query)

  @doc "Generate desk snapshot from live probes"
  def handle_generate(query \\ %{}) do
    Logger.info("[DeskOperatorSnapshotHandler] Starting desk snapshot")

    live = Map.get(query, "live", true)
    task_limit = Map.get(query, "task_limit", 50)

    case generate_snapshot(live, task_limit) do
      {:ok, response} ->
        Logger.info("[DeskOperatorSnapshotHandler] Snapshot generated")
        response

      {:error, reason} ->
        Logger.error("[DeskOperatorSnapshotHandler] Failed: #{inspect(reason)}")

        %{
          "ok" => false,
          "error" => "Failed to generate desk snapshot: #{inspect(reason)}",
          "code" => "generation_failed",
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
    end
  end

  defp generate_snapshot(live, task_limit) do
    try do
      chronicle_brief =
        if live do
          try do
            fetch_chronicle_brief_with_retry(task_limit)
          rescue
            _ -> nil
          end
        else
          nil
        end

      unassigned_tasks =
        if live do
          try do
            fetch_unassigned_tasks_with_retry()
          rescue
            _ -> []
          end
        else
          []
        end

      bot_versions =
        try do
          fetch_bot_versions_with_retry()
        rescue
          _ -> []
        end

      snapshot = %{
        "chronicle_brief" => chronicle_brief,
        "unassigned_tasks" => unassigned_tasks,
        "bot_versions" => bot_versions,
        "desk_generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "live" => live
      }

      {:ok,
       %{
         "ok" => true,
         "schema_version" => "1.0",
         "data" => snapshot,
         "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
       }}
    rescue
      e ->
        Logger.error("[DeskOperatorSnapshotHandler] Exception: #{inspect(e)}")
        {:error, e}
    end
  end

  defp fetch_chronicle_brief_with_retry(task_limit) do
    retry_with_backoff(fn -> fetch_chronicle_brief(task_limit) end, @max_retries)
  end

  defp fetch_chronicle_brief(task_limit) do
    payload = %{
      "presentation" => "plain",
      "choice" => "stabilize",
      "task_limit" => task_limit,
      "live" => true
    }

    with {:ok, json} <- safe_json_encode(payload),
         {:ok, response} <-
           safe_nats_call(fn conn ->
             Gnat.request(conn, "bridge.chronicle.daily.brief", json, receive_timeout: 15_000)
           end),
         {:ok, decoded} <- safe_json_decode(response.body) do
      if decoded["ok"] do
        {:ok, decoded["data"] || %{}}
      else
        Logger.warn(
          "[DeskOperatorSnapshotHandler] Bridge brief returned error: #{inspect(decoded)}"
        )

        {:error, decoded["error"] || "Bridge brief error"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_unassigned_tasks_with_retry do
    retry_with_backoff(fn -> fetch_unassigned_tasks() end, @max_retries)
  end

  defp fetch_unassigned_tasks do
    payload = %{
      "query" => "*",
      "filters" => %{"no_project" => true, "status" => "active"},
      "limit" => 100,
      "offset" => 0
    }

    with {:ok, json} <- safe_json_encode(payload),
         {:ok, response} <-
           safe_nats_call(fn conn ->
             Gnat.request(conn, "bridge.task.search", json, receive_timeout: 15_000)
           end),
         {:ok, decoded} <- safe_json_decode(response.body) do
      if decoded["ok"] do
        tasks = get_in(decoded, ["data", "tasks"]) || []
        {:ok, tasks}
      else
        Logger.warn(
          "[DeskOperatorSnapshotHandler] Task search returned error: #{inspect(decoded)}"
        )

        {:error, decoded["error"] || "Task search error"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_bot_versions_with_retry do
    retry_with_backoff(fn -> fetch_bot_versions() end, @max_retries)
  end

  defp fetch_bot_versions do
    case safe_nats_call(fn conn ->
           Gnat.request(conn, "bot_army.registry.bots.list", "{}", receive_timeout: 10_000)
         end) do
      {:ok, response} ->
        case safe_json_decode(response.body) do
          {:ok, data} ->
            bots = get_in(data, ["data", "bots"]) || []

            versions =
              bots
              |> Enum.map(&%{"name" => &1["name"], "version" => &1["version"]})
              |> Enum.sort_by(& &1["name"])

            {:ok, versions}

          {:error, reason} ->
            Logger.warn("[DeskOperatorSnapshotHandler] Registry parse failed: #{inspect(reason)}")
            {:error, "Registry parse failed"}
        end

      {:error, reason} ->
        Logger.warn("[DeskOperatorSnapshotHandler] Registry fetch failed: #{inspect(reason)}")
        {:error, {:registry_fetch_failed, reason}}
    end
  end

  defp safe_nats_call(func) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        func.(conn)

      {:error, reason} ->
        Logger.warn("[DeskOperatorSnapshotHandler] NATS connection failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  rescue
    e ->
      Logger.error("[DeskOperatorSnapshotHandler] Safe NATS call exception: #{inspect(e)}")
      {:error, e}
  end

  defp safe_json_decode(text) do
    case Jason.decode(text) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("[DeskOperatorSnapshotHandler] JSON decode exception: #{inspect(e)}")
      {:error, e}
  end

  defp safe_json_encode(data) do
    case Jason.encode(data) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("[DeskOperatorSnapshotHandler] JSON encode exception: #{inspect(e)}")
      {:error, e}
  end

  defp retry_with_backoff(func, retries_left) do
    case func.() do
      {:ok, result} ->
        result

      {:error, reason} ->
        if retries_left > 0 do
          Logger.debug(
            "[DeskOperatorSnapshotHandler] Retrying after #{@retry_delay_ms}ms (#{retries_left} left)"
          )

          Process.sleep(@retry_delay_ms)
          retry_with_backoff(func, retries_left - 1)
        else
          raise "Max retries exceeded: #{inspect(reason)}"
        end
    end
  end
end
