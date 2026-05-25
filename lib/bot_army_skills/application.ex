defmodule BotArmySkills.Application do
  @moduledoc "OTP Application for the Skills bot. Manages skill cache and NATS consumers."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BotArmySkills.Repo,
      BotArmyRuntime.Ecto.Repo,
      BotArmySkills.SkillCache,
      BotArmySkills.PulsePublisher,
      BotArmySkills.NATS.Consumer,
      BotArmySkills.HealthWatcher
    ]

    opts = [strategy: :one_for_one, name: BotArmySkills.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
