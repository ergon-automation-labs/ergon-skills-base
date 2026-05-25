defmodule BotArmySkills.Actions.NatsPublish do
  @moduledoc """
  NATS publish action handler — publish to a NATS subject.

  Config:
    - `subject` (required unless using `subject_key`) — The NATS subject to publish to
    - `subject_key` (optional) — payload key containing dynamic target subject
    - `allowed_subject_prefixes` (optional) — list of allowed prefixes for subject validation
    - `envelope` (optional) — Whether to wrap payload in standard envelope (default: true)
  """

  @behaviour BotArmySkills.ActionHandler

  @impl true
  def execute(config, payload) do
    with {:ok, subject} <- resolve_subject(config, payload),
         :ok <- validate_subject(subject, config) do
      envelope? = Map.get(config, "envelope", true)

      message =
        if envelope? do
          %{
            "event" => subject,
            "event_id" => UUID.uuid4(),
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "source" => "bot_army_skills",
            "schema_version" => "1.0",
            "payload" => payload
          }
        else
          payload
        end

      case BotArmyCore.NATS.publish(subject, message) do
        {:ok, _} ->
          {:ok, %{subject: subject, published: true}}

        {:error, reason} ->
          {:error, {:nats_publish_failed, reason}}
      end
    end
  end

  defp resolve_subject(config, payload) do
    subject_key = Map.get(config, "subject_key")

    if is_binary(subject_key) and subject_key != "" do
      case Map.get(payload, subject_key) do
        subject when is_binary(subject) and subject != "" -> {:ok, subject}
        _ -> {:error, {:invalid_or_missing_subject, subject_key}}
      end
    else
      case Map.get(config, "subject") do
        subject when is_binary(subject) and subject != "" -> {:ok, subject}
        _ -> {:error, :missing_subject_config}
      end
    end
  end

  defp validate_subject(subject, config) do
    case Map.get(config, "allowed_subject_prefixes", []) do
      [] ->
        :ok

      prefixes when is_list(prefixes) ->
        if Enum.any?(prefixes, &String.starts_with?(subject, &1)) do
          :ok
        else
          {:error, {:subject_not_allowed, subject}}
        end

      _ ->
        {:error, :invalid_allowed_subject_prefixes}
    end
  end
end
