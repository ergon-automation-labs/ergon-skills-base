import Config

# Runtime configuration — evaluated when the app starts, not at compile time
# This allows environment variables set by launchd/Salt to be read properly

# Database configuration for skills-specific repo (for migrations)
config :bot_army_skills, BotArmySkills.Repo,
  database:
    System.get_env("BOT_ARMY_SKILLS_DB_NAME") || System.get_env("DATABASE_NAME") ||
      "bot_army_skills_dev",
  hostname:
    System.get_env("BOT_ARMY_SKILLS_DB_HOST") || System.get_env("DATABASE_HOST") || "localhost",
  port:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_PORT") || System.get_env("DATABASE_PORT") || "30003"
    ),
  username:
    System.get_env("BOT_ARMY_SKILLS_DB_USER") || System.get_env("DATABASE_USER") || "postgres",
  password:
    System.get_env("BOT_ARMY_SKILLS_DB_PASSWORD") || System.get_env("DATABASE_PASSWORD") ||
      "postgres",
  pool_size:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_POOL_SIZE") ||
        System.get_env("DATABASE_POOL_SIZE") ||
        "5"
    ),
  queue_target:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_QUEUE_TARGET_MS") ||
        System.get_env("DATABASE_QUEUE_TARGET_MS") ||
        "5000"
    ),
  queue_interval:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_QUEUE_INTERVAL_MS") ||
        System.get_env("DATABASE_QUEUE_INTERVAL_MS") ||
        "1000"
    ),
  ssl: false,
  migrations_path: "priv/repo/migrations"

# Database configuration for shared runtime repo used by the skills cache/store.
config :bot_army_library_runtime, BotArmyRuntime.Ecto.Repo,
  database:
    System.get_env("BOT_ARMY_SKILLS_DB_NAME") || System.get_env("DATABASE_NAME") ||
      "bot_army_skills_dev",
  hostname:
    System.get_env("BOT_ARMY_SKILLS_DB_HOST") || System.get_env("DATABASE_HOST") || "localhost",
  port:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_PORT") || System.get_env("DATABASE_PORT") || "30003"
    ),
  username:
    System.get_env("BOT_ARMY_SKILLS_DB_USER") || System.get_env("DATABASE_USER") || "postgres",
  password:
    System.get_env("BOT_ARMY_SKILLS_DB_PASSWORD") || System.get_env("DATABASE_PASSWORD") ||
      "postgres",
  pool_size:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_POOL_SIZE") ||
        System.get_env("DATABASE_POOL_SIZE") ||
        "5"
    ),
  queue_target:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_QUEUE_TARGET_MS") ||
        System.get_env("DATABASE_QUEUE_TARGET_MS") ||
        "5000"
    ),
  queue_interval:
    String.to_integer(
      System.get_env("BOT_ARMY_SKILLS_DB_QUEUE_INTERVAL_MS") ||
        System.get_env("DATABASE_QUEUE_INTERVAL_MS") ||
        "1000"
    ),
  ssl: false,
  migrations_path: "priv/repo/migrations"

# NATS configuration for runtime transport.
nats_host = System.get_env("NATS_HOST") || "localhost"
nats_port = String.to_integer(System.get_env("NATS_PORT") || "4223")

config :bot_army_library_runtime, :nats,
  servers: [{nats_host, nats_port}],
  ping_interval: 30_000,
  max_reconnect_attempts: 10,
  reconnect_delay_ms: 1000

# Auto-start bot_army_runtime services (Registry, NATS connection, etc.)
# This is needed when starting the application manually (not via supervisor)
config :bot_army_library_runtime, :auto_start_services, true

config :bot_army_skills,
       :llm_request_timeout_ms,
       String.to_integer(System.get_env("BOT_ARMY_SKILLS_LLM_REQUEST_TIMEOUT_MS") || "180000")
