# Canonical skills (`priv/canonical_skills/`)

Git-reviewed markdown templates that seed or stay aligned with `bot_army_skills` Postgres rows (tenant-scoped runtime copies). Skill runners resolve `{{ action:slug }}` per tenant.

## Base skills (this repo)

| File | `slug` | Role |
|------|--------|------|
| `bionic_reading.md` | `bionic_reading` | Algorithmic text transformation (no LLM) |
| `bot_log_search.md` | `bot_log_search` | Regex search over bot log files |
| `summarize.md` | `summarize` | LLM-powered text summarization |
| `extract_entities.md` | `extract_entities` | Named entity extraction |
| `draft_message.md` | `draft_message` | Draft messages in a bot's voice |
| `nats_broker_call.md` | `nats_broker_call` | Route requests through bridge subjects |
| `ntp_atomic_time_localize.md` | `ntp_atomic_time_localize` | NTP-backed time localization |
| `playwright_operator.md` | `playwright_operator` | Browser automation guidance |
| `youtube_transcript_pull.md` | `youtube_transcript_pull` | YouTube transcript retrieval |
| `test_simple.md` | `test_simple` | Test skill with no actions |
| `world_snapshot_narrated.md` | `world_snapshot_narrated` | RPG world snapshot formatting |
| `desk_operator_snapshot.md` | `desk_operator_snapshot` | Deterministic desk assembly from bridge/registry probes |

## Adding custom skills

Place `.md` files with YAML frontmatter in this directory and run `mix skills.seed`. The seeder scans all `.md` files and upserts them into the database.