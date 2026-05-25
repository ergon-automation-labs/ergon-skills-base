defmodule BotArmySkills.Handlers.DeskOperatorSnapshotHandlerTest do
  use ExUnit.Case
  @moduletag :handlers

  alias BotArmySkills.Handlers.DeskOperatorSnapshotHandler

  test "handle_generate returns snapshot with live=false" do
    result = DeskOperatorSnapshotHandler.handle_generate(%{"live" => false})

    assert result["ok"] == true
    assert result["schema_version"] == "1.0"
    assert is_map(result["data"])
    assert result["data"]["live"] == false
    assert is_list(result["data"]["bot_versions"])
    assert is_list(result["data"]["unassigned_tasks"])
    assert is_binary(result["data"]["desk_generated_at"])
    assert is_binary(result["timestamp"])
  end

  test "handle_generate accepts live parameter" do
    result = DeskOperatorSnapshotHandler.handle_generate(%{"live" => true, "task_limit" => 25})

    assert is_map(result)
    assert Map.has_key?(result, "ok")
  end

  test "handle_generate uses default task_limit" do
    result = DeskOperatorSnapshotHandler.handle_generate(%{})

    assert is_map(result)
    assert Map.has_key?(result, "ok")
  end
end
