# ergon-skills-base

The extensible Bot Army skills platform — NATS-driven skill execution, template rendering, and action dispatch.

This repo contains the **base platform** with general-purpose skills. Specialized skills live in downstream packages that extend this one via the handler registry.

## What's Included

### Platform Core

- **SkillRunner** — LLM-driven skill execution via NATS request/reply
- **TemplateRenderer** — `{{payload.key}}`, `{{action:slug}}`, `{{context.key}}`, `{{soul.key}}` variable substitution
- **ActionExecutor** — Resolves `{{action:slug}}` references to tenant action configs
- **SkillCache** — ETS-backed per-tenant skill cache with NATS invalidation
- **SkillStore** — Database access layer for skills and tenant actions
- **NATS Consumer** — Subscribes to skill invocation commands, routes to handlers via registry
- **HealthWatcher** — Monitors `system.health`, triggers configured incident handlers
- **PulsePublisher** — Periodic health and pulse broadcasts

### General Skills (12)

| Slug | Description |
|------|-------------|
| `bionic_reading` | Algorithmic text transformation (no LLM) |
| `bot_log_search` | Regex search over bot log files |
| `summarize` | LLM-powered text summarization |
| `extract_entities` | Named entity extraction |
| `draft_message` | Draft messages in a bot's voice |
| `nats_broker_call` | Route requests through bridge subjects |
| `ntp_atomic_time_localize` | NTP-backed time localization |
| `playwright_operator` | Browser automation guidance |
| `youtube_transcript_pull` | YouTube transcript retrieval |
| `test_simple` | Test skill with no actions |
| `world_snapshot_narrated` | RPG world snapshot formatting |
| `desk_operator_snapshot` | Deterministic fact assembly from bridge/registry probes |

### General Handlers (5)

| Handler | Subjects | Notes |
|---------|----------|-------|
| `ContentHandler` | `content.list`, `content.get` | Read-only skill catalog from DB cache |
| `CatalogHandler` | `catalog.canonical`, `catalog.suggest` | Canonical skill install catalog |
| `BionicReadingHandler` | `bionic_reading.transform` | Algorithmic, no LLM |
| `BotLogSearchHandler` | `bot_log_search` | Regex log search |
| `DeskOperatorSnapshotHandler` | `desk_operator_snapshot.generate` | Uses `bridge.*` subjects; swap in config for non-bridge environments |

### Action Types

`webhook`, `nats_publish`, `nats_request`, `api_call`, `slack`, `email`, `no_op`

## Handler Registry (Extensibility)

Handlers implement the `BotArmySkills.Handler` behaviour:

```elixir
@behaviour BotArmySkills.Handler

@impl Handler
def subjects do
  [
    %{subject: "bot.army.skills.my_thing.generate", type: :request_reply, description: "..."}
  ]
end

@impl Handler
def handle_message("bot.army.skills.my_thing.generate", query) do
  # handle the request
end
```

Register handlers in config:

```elixir
config :bot_army_skills, :handlers, [
  BotArmySkills.Handlers.ContentHandler,
  BotArmySkills.Handlers.CatalogHandler,
  BotArmySkills.Handlers.BionicReadingHandler,
  BotArmySkills.Handlers.BotLogSearchHandler,
  BotArmySkills.Handlers.DeskOperatorSnapshotHandler,
  MyApp.Handlers.MyCustomHandler  # your extension
]
```

The consumer discovers all registered handlers at startup and builds its subscription and dispatch map automatically. No consumer edits required.

## Custom Skill Executors

Some skills need a custom execution path (not the default LLM prompt/complete cycle). Register a custom executor by slug:

```elixir
config :bot_army_skills, :custom_executors, %{
  "my_custom_skill" => MyApp.Executors.MyCustomExecutor
}
```

The executor must implement `execute(skill, payload, opts)` returning `{:ok, map()} | {:error, term()}`.

## Incident Report Handler

HealthWatcher can trigger an incident report handler when a service reports degraded/unhealthy status:

```elixir
config :bot_army_skills, :incident_report_handler, MyApp.Handlers.IncidentReportHandler
```

If not configured, HealthWatcher logs the status change but does not generate a report.

## Setup

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
mix skills.seed
```

## Running Tests

```bash
mix test
```

## Architecture

```
NATS message → Consumer → Handler registry dispatch
                        → SkillRunner → TemplateRenderer → LLM → ActionExecutor
                        → SkillCache (ETS) ←→ PostgreSQL
```

## License

Apache 2.0