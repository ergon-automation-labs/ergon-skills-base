---
name: desk-operator-snapshot
slug: desk_operator_snapshot
description: Deterministic desk assembly for operator reports — bridge GTD/registry probes, hygiene slices, optional control-plane metrics.
triggers: bot.army.command.desk_operator_snapshot
llm_hint: none
---

You are the **desk** layer for operator reports: **facts only**, no gazette metaphor unless a downstream skill asks for it.

## Inputs

Synapse / job runner should pass `payload` with at least:

- `tenant_id` — UUID string; must match bridge-injected tenant on every `bridge.*` call.
- Optional `task_limit` — cap for list-style probes (default 50, max 500 where bridge allows).
- Optional `live` — when `false`, skip expensive NATS probes where the handler supports it (e.g. `bridge.chronicle.daily.brief` with `live: false`).

## Execution order (deterministic)

Run these **before** any LLM gazette pass. Use `{{ action:… }}` bindings configured per tenant (see `tenant_actions` in the skill platform north star).

1. **`bridge.chronicle.daily.brief`** — `presentation: "plain"` or `"chronicle"` per policy; include `choice`, `task_limit`, `live`. Canonical response: `schemas/bridge/bridge_chronicle_daily_brief_response.schema.json`. Doc: [PI_GO_BRIDGE_SUBJECTS.md](../../../docs/PI_GO_BRIDGE_SUBJECTS.md) → *Chronicle daily brief façade*.
2. **`bridge.task.search`** — GTD hygiene: unassigned active work — body example:
   ```json
   {"filters": {"no_project": true, "status": "active"}, "limit": 100, "offset": 0}
   ```
   (Query may be omitted; bridge resolves to `*`.) Doc: same PI_GO file → *Task search façade — unassigned tasks*.
3. **`bridge.task.list`** / **`bridge.project.list`** — when you need raw caps not covered by the brief snapshot; respect `tenant_id` and pagination.
4. Optional **`make risk-health`** equivalent — if the runner exposes a `{{ action:risk_health_snapshot }}` or forwards subprocess output, attach **verbatim** excerpts; never invent exit codes or DLQ paths.

## Rules

- Never substitute fiction for **`task_id`**, **`project_id`**, counts, or `ok` / error fields.
- Stable operator entrypoints remain in **`config/ops_catalog.toml`** (regenerate **`docs/OPERATOR_INDEX.md`** with `make ops-catalog-index` when the catalog changes).
- Multi-tenant: each run is scoped by **`tenant_id`**`; do not mix two tenants in one snapshot.

## Output

Return structured JSON for downstream skills (gazette / PARA / Discord), e.g.:

- `chronicle_brief` — raw `bridge.chronicle.daily.brief` body
- `unassigned_tasks` — `tasks` array from `bridge.task.search` with `no_project`
- `desk_generated_at` — ISO-8601 UTC

Markdown narration is **out of scope** for this skill; use **`chronicle_daily_brief_compose`** or Synapse edition builders for prose.
