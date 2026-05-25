defmodule BotArmySkills do
  @moduledoc """
  Database-driven, tenant-scoped skill platform for the Bot Army.

  Skills are defined as markdown templates stored in PostgreSQL, scoped per tenant.
  Templates support variable substitution:

    - `{{payload.key}}` — from the incoming NATS message
    - `{{action:slug}}` — resolved from the tenant_actions table at runtime
    - `{{context.key}}` — from the Context Broker state
    - `{{soul.key}}` — from the bot's personality/Soul configuration

  This library works alongside the existing `BotArmy.Skill` behaviour and
  `BotArmy.GenBot` macro. Bots opt in by adding `db_skills: true` to their
  GenBot configuration.
  """
end
