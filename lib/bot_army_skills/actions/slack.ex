defmodule BotArmySkills.Actions.Slack do
  @moduledoc """
  Slack action handler — post to a Slack webhook.

  Config:
    - `webhook_url` (required) — The Slack incoming webhook URL
    - `channel` (optional) — Override channel (uses webhook default if not set)
    - `username` (optional) — Override bot username
    - `icon_emoji` (optional) — Override bot icon
  """

  @behaviour BotArmySkills.ActionHandler

  @impl true
  def execute(config, payload) do
    webhook_url = Map.fetch!(config, "webhook_url")

    slack_payload =
      %{
        text: format_text(payload),
        channel: Map.get(config, "channel"),
        username: Map.get(config, "username"),
        icon_emoji: Map.get(config, "icon_emoji")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(webhook_url, Jason.encode!(slack_payload), headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: "ok"}} ->
        {:ok, %{sent: true, channel: Map.get(config, "channel")}}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, {:slack_failed, code, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:slack_error, reason}}
    end
  end

  defp format_text(payload) when is_map(payload) do
    case Map.get(payload, "text") do
      nil -> Jason.encode!(payload)
      text -> text
    end
  end

  defp format_text(payload), do: inspect(payload)
end
