defmodule BotArmySkills.Handlers.BotLogSearchHandler do
  @moduledoc "Handler for searching bot logs with regex and context"
  @behaviour BotArmySkills.Handler
  require Logger

  @log_dir "/var/log/bot_army"
  @context_lines 2

  @doc "Search bot logs by name and regex query"
  def handle_search(query \\ %{}) do
    Logger.info("[BotLogSearchHandler] Starting log search: #{inspect(query)}")

    bot_name = query["bot_name"] || query["bot"]
    regex_pattern = query["query"] || query["pattern"]

    case {bot_name, regex_pattern} do
      {nil, nil} ->
        error_response("Missing required parameters: bot_name and query")

      {nil, _} ->
        search_all_bots(regex_pattern)

      {bot, nil} ->
        error_response("Missing required parameter: query")

      {bot, pattern} ->
        search_bot_logs(bot, pattern)
    end
  end

  defp search_bot_logs(bot_name, regex_pattern) do
    log_files = [
      Path.join(@log_dir, "#{bot_name}.log"),
      Path.join(@log_dir, "#{bot_name}.err")
    ]

    case compile_regex(regex_pattern) do
      {:ok, regex} ->
        results =
          log_files
          |> Enum.filter(&File.exists?/1)
          |> Enum.map(&search_file(&1, regex))
          |> Enum.concat()

        %{
          "ok" => true,
          "bot" => bot_name,
          "query" => regex_pattern,
          "matches" => length(results),
          "results" => Enum.take(results, 100),
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

      {:error, reason} ->
        error_response("Invalid regex: #{inspect(reason)}")
    end
  end

  defp search_all_bots(regex_pattern) do
    case compile_regex(regex_pattern) do
      {:ok, regex} ->
        case File.ls(@log_dir) do
          {:ok, files} ->
            results =
              files
              |> Enum.filter(&String.ends_with?(&1, ".log"))
              |> Enum.map(&Path.join(@log_dir, &1))
              |> Enum.map(&search_file(&1, regex))
              |> Enum.concat()

            %{
              "ok" => true,
              "bot" => "all",
              "query" => regex_pattern,
              "matches" => length(results),
              "results" => Enum.take(results, 100),
              "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
            }

          {:error, reason} ->
            error_response("Failed to read log directory: #{inspect(reason)}")
        end

      {:error, reason} ->
        error_response("Invalid regex: #{inspect(reason)}")
    end
  end

  defp search_file(file_path, regex) do
    case File.read(file_path) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        lines
        |> Enum.with_index()
        |> Enum.filter(fn {line, _idx} ->
          String.match?(line, regex)
        end)
        |> Enum.map(fn {line, idx} ->
          context_before =
            lines
            |> Enum.slice(max(0, idx - @context_lines)..(idx - 1))
            |> Enum.join("\n")

          context_after =
            lines
            |> Enum.slice((idx + 1)..min(length(lines) - 1, idx + @context_lines))
            |> Enum.join("\n")

          %{
            "file" => Path.basename(file_path),
            "line_number" => idx + 1,
            "match" => line,
            "context_before" => context_before,
            "context_after" => context_after
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  defp compile_regex(pattern) do
    try do
      {:ok, Regex.compile!(pattern)}
    rescue
      e -> {:error, e}
    end
  end

  @impl BotArmySkills.Handler
  def subjects do
    [
      %{
        subject: "bot.army.skills.bot_log_search",
        type: :request_reply,
        description: "Search bot logs by regex with context (specify bot_name or search all)"
      }
    ]
  end

  @impl BotArmySkills.Handler
  def handle_message("bot.army.skills.bot_log_search", query), do: handle_search(query)

  defp error_response(message) do
    %{
      "ok" => false,
      "error" => message,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
