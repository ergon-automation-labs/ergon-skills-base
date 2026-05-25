defmodule BotArmySkills.ActionExecutorTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.ActionExecutor

  describe "list_action_slugs/1" do
    test "extracts action slugs from template" do
      template = "Notify via {{ action:notify_team }} and {{ action:page_oncall }}"

      assert ActionExecutor.list_action_slugs(template) == ["notify_team", "page_oncall"]
    end

    test "returns empty list when no action slugs" do
      template = "No actions here, just {{ payload.content }}"

      assert ActionExecutor.list_action_slugs(template) == []
    end

    test "deduplicates action slugs" do
      template = "First: {{ action:notify_team }}, Second: {{ action:notify_team }}"

      assert ActionExecutor.list_action_slugs(template) == ["notify_team"]
    end

    test "handles whitespace around slug" do
      template = "{{ action:  notify_team  }}"

      assert ActionExecutor.list_action_slugs(template) == ["notify_team"]
    end

    test "only matches valid slug characters" do
      template = "{{ action:valid_slug }} and {{ payload.not_an_action }}"

      assert ActionExecutor.list_action_slugs(template) == ["valid_slug"]
    end
  end

  describe "execute/3" do
    test "returns error when action not found" do
      # Without DB, get_action will fail — catch that and verify the contract
      result = ActionExecutor.execute("tenant-123", "nonexistent", %{})
      assert match?({:error, _}, result)
    end
  end
end
