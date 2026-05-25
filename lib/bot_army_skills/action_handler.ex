defmodule BotArmySkills.ActionHandler do
  @moduledoc """
  Behaviour for tenant action type handlers.

  Each action type (webhook, nats_publish, api_call, slack, email)
  implements this behaviour to handle execution of its specific type.
  """

  @callback execute(config :: map(), payload :: map()) ::
              {:ok, map()} | {:error, term()}
end
