defmodule BotArmySkills.SkillExecutor do
  @moduledoc """
  Registry for custom skill executors that bypass the normal LLM-driven path.

  Register a custom executor for a slug in config:

      config :bot_army_skills, :custom_executors, %{
        "my_custom_skill" => MyApp.Executors.MyCustomExecutor
      }

  The executor module must implement `execute/3`:
  - `execute(skill, payload, opts)` returns `{:ok, map()} | {:error, term()}`
  """

  @spec lookup(String.t()) :: module() | nil
  def lookup(slug) do
    Map.get(executors(), slug)
  end

  defp executors do
    Application.get_env(:bot_army_skills, :custom_executors, %{})
  end
end
