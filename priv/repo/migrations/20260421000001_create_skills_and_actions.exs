defmodule BotArmySkills.Repo.Migrations.CreateSkillsAndActions do
  @moduledoc """
  Creates skills and tenant_actions tables.

  This migration must be copied into and run by each bot that opts into
  DB-driven skills (`db_skills: true`). It creates the tables in that
  bot's own database.

  Usage:
    1. Copy this file to <bot>/priv/repo/migrations/
    2. Rename the module to match the bot's namespace
    3. Run `mix ecto.migrate` in the bot directory
  """

  use Ecto.Migration

  def up do
    create table(:skills, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:tenant_id, :uuid, null: false)
      add(:name, :text, null: false)
      add(:slug, :text, null: false)
      add(:markdown_content, :text, null: false)
      add(:version, :integer, null: false, default: 1)
      add(:is_active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:skills, [:tenant_id, :slug, :version]))

    create(
      index(:skills, [:tenant_id, :slug, :is_active],
        where: "is_active = true",
        name: :idx_skills_tenant_slug_active
      )
    )

    create(
      index(:skills, [:tenant_id, :is_active],
        where: "is_active = true",
        name: :idx_skills_tenant_active
      )
    )

    create table(:tenant_actions, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:tenant_id, :uuid, null: false)
      add(:slug, :text, null: false)
      add(:type, :text, null: false)
      add(:config_json, :jsonb, null: false, default: "{}")
      add(:is_active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:tenant_actions, [:tenant_id, :slug]))

    create(
      index(:tenant_actions, [:tenant_id, :is_active],
        where: "is_active = true",
        name: :idx_tenant_actions_tenant_active
      )
    )
  end

  def down do
    drop(table(:tenant_actions))
    drop(table(:skills))
  end
end
