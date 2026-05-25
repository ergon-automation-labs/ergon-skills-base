defmodule BotArmySkills.TenantAction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @action_types ~w(webhook nats_publish nats_request api_call slack email)

  schema "tenant_actions" do
    field(:tenant_id, :binary_id)
    field(:slug, :string)
    field(:type, :string)
    field(:config_json, :map, default: %{})
    field(:is_active, :boolean, default: true)
    timestamps(type: :utc_datetime)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [:tenant_id, :slug, :type, :config_json, :is_active])
    |> validate_required([:tenant_id, :slug, :type, :config_json])
    |> validate_inclusion(:type, @action_types)
    |> validate_format(:slug, ~r/^[a-z][a-z0-9_]*$/)
  end

  def action_types, do: @action_types
end
