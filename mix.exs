defmodule BotArmySkills.MixProject do
  use Mix.Project

  def project do
    [
      app: :bot_army_skills,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        skills_bot: [
          applications: [bot_army_skills: :permanent]
        ]
      ],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BotArmySkills.Application, []}
    ]
  end

  defp deps do
    [
      {:bot_army_library_core,
       git: "https://github.com/ergon-automation-labs/ergon-library-core.git", branch: "main"},
      {:bot_army_library_runtime,
       git: "https://github.com/ergon-automation-labs/ergon-library-runtime.git", branch: "main"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.4"},
      {:logger_json, "~> 5.1"},
      {:httpoison, "~> 2.0"},
      {:gnat, "~> 1.2"},
      {:elixir_uuid, "~> 1.2"},

      # Dev/Test
      {:ex_doc, "~> 0.30", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.17", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
