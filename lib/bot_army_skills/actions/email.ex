defmodule BotArmySkills.Actions.Email do
  @moduledoc """
  Email action handler — publishes to a NATS subject for email delivery.

  This handler does not send email directly. It publishes a message to
  `bot.army.email.send` which an email bot processes for delivery.

  Config:
    - `to` (required) — Recipient email address or list of addresses
    - `subject_template` (optional) — Subject line template with {{payload.*}} substitution
    - `from` (optional) — Sender address (uses default if not set)
  """

  @behaviour BotArmySkills.ActionHandler

  @impl true
  def execute(config, payload) do
    to = Map.fetch!(config, "to")

    subject =
      render_subject(Map.get(config, "subject_template", "Bot Army Notification"), payload)

    from = Map.get(config, "from")

    message =
      %{
        "to" => to,
        "subject" => subject,
        "from" => from,
        "payload" => payload,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case BotArmyCore.NATS.publish("bot.army.email.send", message) do
      {:ok, _} ->
        {:ok, %{queued: true, to: to, subject: subject}}

      {:error, reason} ->
        {:error, {:email_publish_failed, reason}}
    end
  end

  defp render_subject(template, payload) do
    Regex.replace(~r/\{\{\s*payload\.([a-zA-Z0-9_.]+)\s*\}\}/, template, fn _match, path ->
      path
      |> String.split(".")
      |> resolve_path(payload)
    end)
  end

  defp resolve_path(path_parts, data) do
    case get_in(data, path_parts) do
      nil -> ""
      value when is_binary(value) -> value
      value -> inspect(value)
    end
  rescue
    _ -> ""
  end
end
