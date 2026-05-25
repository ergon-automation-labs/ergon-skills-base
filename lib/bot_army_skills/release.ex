defmodule BotArmySkills.Release do
  @moduledoc """
  Release tasks for the skills bot.

  Migrations are run via the shared BotArmyRuntime.Ecto.MigrationRunner:

      /path/to/skills_bot/bin/skills_bot eval 'BotArmySkills.Release.migrate()'
      /path/to/skills_bot/bin/skills_bot eval 'BotArmySkills.Release.migrate_and_seed()'

  Called from Salt during bot deployment, before the bot starts.
  """

  alias BotArmyRuntime.Ecto.MigrationRunner

  @app :bot_army_skills

  def migrate do
    MigrationRunner.run(
      repo_module: BotArmySkills.Repo,
      app_module: @app
    )
  end

  def migrate_and_seed do
    load_app()

    # In a release, manually load the runtime configuration since runtime.exs
    # may not be loaded when Release.* functions run
    load_runtime_config()

    # Ensure required dependencies are started
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    # Start both repos that will be needed during migrations and seeding
    {:ok, _} = BotArmySkills.Repo.start_link(pool_size: 2)
    {:ok, _} = BotArmyRuntime.Ecto.Repo.start_link(pool_size: 2)

    # Run migrations directly (repos are already started)
    Ecto.Migrator.run(BotArmySkills.Repo, :up, all: true, migrations_path: migrations_path())

    # Seed after migrations complete
    seed_default_tenant_skills()
  end

  defp migrations_path do
    # Construct absolute path to migrations directory
    # In a release: /path/to/release/lib/bot_army_skills-X.Y.Z/priv/repo/migrations
    # In dev: /path/to/source/priv/repo/migrations
    skills_app_dir = Application.app_dir(@app)
    migrations_dir = Path.join(skills_app_dir, "priv/repo/migrations")

    # Ensure it's an absolute path for Ecto.Migrator
    if Path.type(migrations_dir) == :absolute do
      migrations_dir
    else
      Path.expand(migrations_dir)
    end
  end

  def seed_default_tenant_skills do
    BotArmySkills.Seeder.seed_default_tenant!()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp load_runtime_config do
    # Configure repos from environment in release eval context
    db_name =
      System.get_env("BOT_ARMY_SKILLS_DB_NAME") || System.get_env("DATABASE_NAME") ||
        "bot_army_skills_dev"

    db_host =
      System.get_env("BOT_ARMY_SKILLS_DB_HOST") || System.get_env("DATABASE_HOST") || "localhost"

    db_port =
      String.to_integer(
        System.get_env("BOT_ARMY_SKILLS_DB_PORT") || System.get_env("DATABASE_PORT") || "30003"
      )

    db_user =
      System.get_env("BOT_ARMY_SKILLS_DB_USER") || System.get_env("DATABASE_USER") || "postgres"

    db_pass =
      System.get_env("BOT_ARMY_SKILLS_DB_PASSWORD") || System.get_env("DATABASE_PASSWORD") ||
        "postgres"

    db_config = [
      database: db_name,
      hostname: db_host,
      port: db_port,
      username: db_user,
      password: db_pass,
      pool_size: 2,
      queue_target: 5000,
      queue_interval: 1000,
      ssl: false
    ]

    Application.put_env(:bot_army_skills, BotArmySkills.Repo, db_config)
    Application.put_env(:bot_army_library_runtime, BotArmyRuntime.Ecto.Repo, db_config)
  end
end
