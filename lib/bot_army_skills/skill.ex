defmodule BotArmySkills.Skill do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "skills" do
    field(:tenant_id, :binary_id)
    field(:name, :string)
    field(:slug, :string)
    field(:markdown_content, :string)
    field(:version, :integer, default: 1)
    field(:is_active, :boolean, default: true)
    timestamps(type: :utc_datetime)
  end

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [:tenant_id, :name, :slug, :markdown_content, :version, :is_active])
    |> validate_required([:tenant_id, :name, :slug, :markdown_content, :version])
    |> validate_format(:slug, ~r/^[a-z][a-z0-9_]*$/,
      message:
        "must start with lowercase letter, contain only lowercase letters, digits, underscores"
    )
  end
end
