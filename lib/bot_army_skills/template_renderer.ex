defmodule BotArmySkills.TemplateRenderer do
  @moduledoc """
  Renders skill markdown templates with variable substitution.

  Supports four template variable types:

    - `{{payload.key}}` — from the NATS message payload
    - `{{action:slug}}` — resolved from tenant_actions table at runtime
    - `{{context.key}}` — from the Context Broker state
    - `{{soul.key}}` — from the bot's personality/Soul configuration

  Missing keys render as empty strings (never error).
  Nested paths are supported via dot notation: `{{payload.user.name}}`.
  """

  @type template_vars :: %{
          payload: map(),
          context: map(),
          soul: map(),
          tenant_id: String.t()
        }

  @doc "Render a template string with all variable types resolved."
  @spec render(template :: String.t(), vars :: template_vars()) :: String.t()
  def render(template, vars) when is_binary(template) and is_map(vars) do
    template
    |> render_actions(vars)
    |> render_payload(vars)
    |> render_context(vars)
    |> render_soul(vars)
  end

  # {{action:slug}} -> resolved from tenant_actions
  defp render_actions(template, %{tenant_id: tenant_id} = vars) do
    repo = Map.get(vars, :repo, BotArmyRuntime.Ecto.Repo)

    Regex.replace(~r/\{\{\s*action:([a-z0-9_]+)\s*\}\}/, template, fn _match, slug ->
      try do
        case BotArmySkills.SkillStore.get_action(tenant_id, slug, repo: repo) do
          nil -> "[Action '#{slug}' not found]"
          action -> format_action_reference(action)
        end
      rescue
        _ -> "[Action '#{slug}' not found]"
      end
    end)
  end

  # {{payload.key}} -> from NATS message
  defp render_payload(template, %{payload: payload}) when is_map(payload) do
    Regex.replace(~r/\{\{\s*payload\.([a-zA-Z0-9_.]+)\s*\}\}/, template, fn _match, path ->
      path
      |> String.split(".")
      |> resolve_path(payload)
    end)
  end

  defp render_payload(template, _vars), do: template

  # {{context.key}} -> from Context Broker
  defp render_context(template, %{context: context}) when is_map(context) do
    Regex.replace(~r/\{\{\s*context\.([a-zA-Z0-9_.]+)\s*\}\}/, template, fn _match, path ->
      path
      |> String.split(".")
      |> resolve_path(context)
    end)
  end

  defp render_context(template, _vars), do: template

  # {{soul.key}} -> from personality/Soul config
  defp render_soul(template, %{soul: soul}) when is_map(soul) do
    Regex.replace(~r/\{\{\s*soul\.([a-zA-Z0-9_.]+)\s*\}\}/, template, fn _match, path ->
      path
      |> String.split(".")
      |> resolve_path(soul)
    end)
  end

  defp render_soul(template, _vars), do: template

  defp resolve_path(path_parts, data) do
    case get_in(data, path_parts) do
      nil -> ""
      value when is_binary(value) -> value
      value -> inspect(value)
    end
  rescue
    _ -> ""
  end

  defp format_action_reference(%BotArmySkills.TenantAction{type: type, slug: slug}) do
    "[Action: #{slug} (type: #{type})]"
  end
end
