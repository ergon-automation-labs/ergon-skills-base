---
name: playwright_operator
description: Baseline guidance for browser automation via Playwright (operator context, safety, traces).
llm_hint: none
---

# Playwright operator playbook

Canonical skill for fleet-wide Playwright operator guidance. Runtime copy lives in **`bot_army_skills`** Postgres (default tenant); git source is this file.

## Role

Use when an operator or agent should drive a real browser (navigation, forms, assertions) with Playwright.

## Safety

- Run automation only in **approved** environments; never against production tenant data without explicit scope.
- Prefer **headed vs headless** based on policy; capture **video/trace** on failure.
- Treat selectors as brittle — prefer role/name locators and stable test ids agreed with the app team.

## Flow

1. Define the user goal and **happy path** plus one **failure** case to observe.
2. Stabilize login/session (fixtures, storage state) outside hot paths when possible.
3. After edits, run a **single focused spec** before the full suite.

## Integration note

Executable Playwright belongs in a **sandboxed worker** with a narrow API; this markdown is the **shared procedure** layer until that worker is wired.

- **Read (no LLM):** `bot.army.skills.content.get` with `{"tenant_id":"…","slug":"playwright_operator"}`.
- **After work:** `bot_army.general.operator.complete` (PARA + notification intent).
