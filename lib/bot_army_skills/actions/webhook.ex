defmodule BotArmySkills.Actions.Webhook do
  @moduledoc """
  Webhook action handler — POST to a tenant-defined URL.

  Config:
    - `url` (required) — The webhook endpoint URL
    - `headers` (optional) — Map of HTTP headers
    - `method` (optional) — HTTP method, defaults to "POST"
  """

  @behaviour BotArmySkills.ActionHandler

  @impl true
  def execute(config, payload) do
    url = Map.fetch!(config, "url")
    headers = Map.get(config, "headers", %{"Content-Type" => "application/json"})
    method = Map.get(config, "method", "POST") |> String.downcase() |> String.to_atom()
    body = Jason.encode!(payload)

    case HTTPoison.request(method, url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}}
      when code >= 200 and code < 300 ->
        {:ok, %{status_code: code, body: resp_body}}

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        {:error, {:webhook_failed, code, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:webhook_error, reason}}
    end
  end
end
