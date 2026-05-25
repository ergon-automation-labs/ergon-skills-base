defmodule BotArmySkills.SkillRunnerTest do
  use ExUnit.Case
  @moduletag :core

  alias BotArmySkills.SkillRunner

  test "fills podcast_write from completion when persist_podcast is true" do
    payload = %{
      "persist_podcast" => true,
      "episode_slug" => "terrain-gameshow"
    }

    action_payload =
      SkillRunner.build_action_payload_for_test(payload, "# Episode\n\nDungeon cleared.")

    assert action_payload["skill_completion"] == "# Episode\n\nDungeon cleared."

    assert %{
             "schema_version" => "1.0",
             "mode" => "write",
             "content" => "# Episode\n\nDungeon cleared.",
             "relative_path" => path
           } = action_payload["podcast_write"]

    assert String.starts_with?(path, "resources/learning_podcasts/inbox/")
    assert String.ends_with?(path, "_terrain-gameshow.md")
  end

  test "does not overwrite podcast_write content when already provided" do
    payload = %{
      "persist_podcast" => true,
      "podcast_write" => %{
        "schema_version" => "1.0",
        "mode" => "write",
        "relative_path" => "resources/learning_podcasts/inbox/custom.md",
        "content" => "already written"
      }
    }

    action_payload =
      SkillRunner.build_action_payload_for_test(payload, "new completion")

    assert action_payload["podcast_write"]["content"] == "already written"
  end
end
