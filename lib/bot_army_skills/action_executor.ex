defmodule BotArmySkills.ActionExecutor do
  @moduledoc """
  Executes tenant actions resolved from {{action:slug}} references.

  Each action type has a handler module that implements the
  BotArmySkills.ActionHandler behaviour.

  Action slugs are resolved from the tenant_actions table at runtime,
  then dispatched to the appropriate handler based on type.
  """

  alias BotArmySkills.SkillStore

  @action_handlers %{
    "webhook" => BotArmySkills.Actions.Webhook,
    "nats_publish" => BotArmySkills.Actions.NatsPublish,
    "nats_request" => BotArmySkills.Actions.NatsRequest,
    "api_call" => BotArmySkills.Actions.ApiCall,
    "slack" => BotArmySkills.Actions.Slack,
    "email" => BotArmySkills.Actions.Email
  }

  @doc "Execute an action by slug for a given tenant."
  @spec execute(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(tenant_id, slug, payload, opts \\ []) do
    case get_action_safely(tenant_id, slug, opts) do
      {:ok, %{is_active: false}} ->
        {:error, {:action_inactive, slug}}

      {:ok, %{type: type, config_json: config}} ->
        handler = Map.get(@action_handlers, type, BotArmySkills.Actions.NoOp)
        handler.execute(config, payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Execute all actions found in a template's {{action:slug}} references."
  @spec execute_actions_in_template(String.t(), String.t(), map(), keyword()) ::
          [{String.t(), {:ok, map()} | {:error, term()}}]
  def execute_actions_in_template(tenant_id, template, payload, opts \\ []) do
    ~r/\{\{\s*action:\s*([a-z0-9_]+)\s*\}\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(fn slug ->
      {slug, execute(tenant_id, slug, payload, opts)}
    end)
  end

  @doc "List all action slugs referenced in a template."
  @spec list_action_slugs(String.t()) :: [String.t()]
  def list_action_slugs(template) do
    ~r/\{\{\s*action:\s*([a-z0-9_]+)\s*\}\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp get_action_safely(tenant_id, slug, opts) do
    case SkillStore.get_action(tenant_id, slug, opts) do
      nil -> {:error, {:action_not_found, slug}}
      action -> {:ok, action}
    end
  rescue
    _ -> {:error, {:action_not_found, slug}}
  end
end
