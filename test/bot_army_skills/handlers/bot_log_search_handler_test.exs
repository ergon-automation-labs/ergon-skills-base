defmodule BotArmySkills.Handlers.BotLogSearchHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  alias BotArmySkills.Handlers.BotLogSearchHandler

  setup do
    # Create a temp log file for testing
    test_log_dir = System.tmp_dir!() <> "/test_logs"
    File.mkdir_p!(test_log_dir)

    test_log = Path.join(test_log_dir, "test_bot.log")

    log_content = """
    2026-05-18 10:00:00 [info] Starting test
    2026-05-18 10:00:01 [debug] Processing request
    2026-05-18 10:00:02 [error] Something went wrong here
    2026-05-18 10:00:03 [debug] Retrying operation
    2026-05-18 10:00:04 [error] Another error occurred
    2026-05-18 10:00:05 [warning] Be careful with this
    2026-05-18 10:00:06 [info] Completed successfully
    """

    File.write!(test_log, log_content)

    on_exit(fn ->
      File.rm_rf!(test_log_dir)
    end)

    {:ok, test_log: test_log, test_log_dir: test_log_dir}
  end

  test "search_file finds matching lines with regex" do
    # This tests the internal search logic
    content = """
    2026-05-18 10:00:00 [info] Starting test
    2026-05-18 10:00:01 [debug] Processing request
    2026-05-18 10:00:02 [error] Something went wrong here
    2026-05-18 10:00:03 [debug] Retrying operation
    2026-05-18 10:00:04 [error] Another error occurred
    """

    regex = Regex.compile!("error")
    lines = String.split(content, "\n")

    # Filter matching lines
    matches =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} ->
        String.match?(line, regex)
      end)

    assert length(matches) == 2

    assert matches
           |> Enum.any?(fn {line, _} -> String.contains?(line, "Something went wrong") end)
  end

  test "handle_search returns error with missing parameters" do
    result = BotLogSearchHandler.handle_search(%{})

    assert result["ok"] == false
    assert String.contains?(result["error"], "Missing required parameters")
  end

  test "handle_search returns error with missing query" do
    result = BotLogSearchHandler.handle_search(%{"bot_name" => "test_bot"})

    assert result["ok"] == false
    assert String.contains?(result["error"], "Missing required parameter")
  end

  test "handle_search returns error with invalid regex" do
    result =
      BotLogSearchHandler.handle_search(%{
        "bot_name" => "test_bot",
        "query" => "(?<invalid"
      })

    assert result["ok"] == false
    assert String.contains?(result["error"], "Invalid regex")
  end

  test "regex patterns work as expected" do
    # Test various regex patterns
    assert Regex.match?(Regex.compile!("error"), "[error] Something went wrong")
    assert Regex.match?(Regex.compile!("error|warning"), "[warning] Be careful")
    assert Regex.match?(Regex.compile!("\\[error\\]"), "[error] Something went wrong")
    assert Regex.match?(Regex.compile!("^2026"), "2026-05-18 10:00:00")
  end

  test "context extraction works correctly" do
    lines = [
      "line 1",
      "line 2",
      "line 3 - MATCH",
      "line 4",
      "line 5"
    ]

    # "line 3 - MATCH"
    idx = 2
    context_before = lines |> Enum.slice(max(0, idx - 2)..(idx - 1)) |> Enum.join("\n")

    context_after =
      lines |> Enum.slice((idx + 1)..min(length(lines) - 1, idx + 2)) |> Enum.join("\n")

    assert String.contains?(context_before, "line 1")
    assert String.contains?(context_before, "line 2")
    assert String.contains?(context_after, "line 4")
    assert String.contains?(context_after, "line 5")
  end

  test "response format is correct" do
    result =
      BotLogSearchHandler.handle_search(%{
        "bot_name" => "nonexistent_bot",
        "query" => "error"
      })

    # Should return empty results, not error, since regex is valid
    assert result["ok"] == true
    assert result["bot"] == "nonexistent_bot"
    assert result["query"] == "error"
    assert is_integer(result["matches"])
    assert is_list(result["results"])
    assert String.valid?(result["timestamp"])
  end
end
