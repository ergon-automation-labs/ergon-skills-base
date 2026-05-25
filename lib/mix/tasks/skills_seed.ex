defmodule Mix.Tasks.Skills.Seed do
  use Mix.Task

  @shortdoc "Seed canonical skills into the default tenant"

  @moduledoc """
  Seeds canonical skill definitions from priv/canonical_skills/ into the
  database for the default tenant.

  ## Usage

      mix skills.seed
  """

  def run(_args) do
    Mix.Task.run("app.start", [])

    results = BotArmySkills.Seeder.seed_default_tenant!()

    success_count = Enum.count(results, &(&1 == :ok))
    error_count = Enum.count(results, &match?({:error, _}, &1))

    Mix.shell().info("Seeded #{success_count} skills, #{error_count} errors")
  end
end
