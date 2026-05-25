import Config

config :bot_army_skills,
  ecto_repos: [BotArmySkills.Repo, BotArmyRuntime.Ecto.Repo],
  handlers: [
    BotArmySkills.Handlers.ContentHandler,
    BotArmySkills.Handlers.CatalogHandler,
    BotArmySkills.Handlers.BionicReadingHandler,
    BotArmySkills.Handlers.BotLogSearchHandler,
    BotArmySkills.Handlers.DeskOperatorSnapshotHandler
  ],
  custom_executors: %{},
  incident_report_handler: nil

# Keep this value set at compile-time to match runtime.exs and avoid
# release boot validation failures in releases, while preventing test
# runs from starting bound services (metrics/NATS listeners).
config :bot_army_library_runtime, :auto_start_services, config_env() != :test

env_config = "#{config_env()}.exs"
env_config_path = Path.join(__DIR__, env_config)

if File.exists?(env_config_path) do
  import_config env_config
end
