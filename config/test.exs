import Config

config :bot_army_skills, BotArmySkills.Repo,
  database: "bot_army_skills_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  migrations_path: "priv/repo/migrations"
