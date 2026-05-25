import Config

config :bot_army_skills, BotArmySkills.Repo,
  database: "bot_army_skills_dev",
  pool_size: 10,
  migrations_path: "priv/repo/migrations"

config :bot_army_library_runtime, BotArmyRuntime.Ecto.Repo,
  database: "bot_army_skills_dev",
  pool_size: 10,
  migrations_path: "priv/repo/migrations"
