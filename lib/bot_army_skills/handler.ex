defmodule BotArmySkills.Handler do
  @moduledoc """
  Behaviour for NATS handler modules.

  Each handler declares the NATS subjects it serves and implements
  message handling. The consumer discovers handlers from application
  config and dispatches inbound messages without hard-coded case statements.
  """

  @type subject_spec :: %{
          subject: String.t(),
          type: :request_reply | :subscribe,
          description: String.t()
        }

  @callback subjects() :: [subject_spec()]
  @callback handle_message(topic :: String.t(), query :: map()) :: map()
end
