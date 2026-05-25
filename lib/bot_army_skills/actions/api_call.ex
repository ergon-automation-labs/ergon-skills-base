defmodule BotArmySkills.Actions.ApiCall do
  @moduledoc """
  Generic HTTP API call action handler.

  Config:
    - `url` (required) — The API endpoint URL
    - `method` (optional) — HTTP method, defaults to "POST"
    - `headers` (optional) — Map of HTTP headers
    - `body_template` (optional) — Template for the request body; uses {{payload.*}} substitution
  """

  @behaviour BotArmySkills.ActionHandler

  @impl true
  def execute(config, payload) do
    url = Map.fetch!(config, "url")
    method = Map.get(config, "method", "POST") |> String.downcase() |> String.to_atom()
    headers = Map.get(config, "headers", %{"Content-Type" => "application/json"})

    body =
      case Map.get(config, "body_template") do
        nil -> Jason.encode!(payload)
        template -> render_body_template(template, payload)
      end

    header_list = Enum.map(headers, fn {k, v} -> {String.to_atom(k), v} end)

    case HTTPoison.request(method, url, body, header_list) do
      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}}
      when code >= 200 and code < 300 ->
        {:ok, %{status_code: code, body: resp_body}}

      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} ->
        {:error, {:api_call_failed, code, resp_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:api_call_error, reason}}
    end
  end

  defp render_body_template(template, payload) do
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
