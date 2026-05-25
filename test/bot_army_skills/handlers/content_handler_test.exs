defmodule BotArmySkills.Handlers.ContentHandlerTest do
  use ExUnit.Case, async: true

  alias BotArmySkills.Handlers.ContentHandler

  @moduletag :handlers

  test "handle_get/1 requires slug" do
    assert %{"error" => "missing_slug"} = ContentHandler.handle_get(%{})
  end

  test "handle_get/1 returns not found for unknown slug" do
    assert %{"error" => "skill_not_found", "slug" => "no_such_skill"} =
             ContentHandler.handle_get(%{"slug" => "no_such_skill"})
  end
end
