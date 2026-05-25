defmodule BotArmySkills.Actions.NoOp do
  @moduledoc """
  Fallback handler for unknown action types.
  Returns {:ok, %{skipped: true}} without performing any action.
  """

  @behaviour BotArmySkills.ActionHandler

  @impl true
  def execute(_config, _payload) do
    {:ok, %{skipped: true}}
  end
end
