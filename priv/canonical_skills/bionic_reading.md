---
name: bionic_reading
slug: bionic_reading
description: Transform text with bionic reading formatting (bold first portion of each word to guide the eye)
triggers: bot.army.skills.bionic_reading.transform
llm_hint: none
---

## Bionic Reading

This skill transforms text using the bionic reading method, which bolds the first portion of each word to guide the eye and improve reading speed and comprehension.

**This is an algorithmic skill — no LLM call is made.** The transformation is handled by a dedicated NATS handler for instant, deterministic results.

### Request Format

```json
{
  "text": "The quick brown fox jumps over the lazy dog",
  "ratio": 0.3,
  "format": "markdown"
}
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `text` | string | "" | Text to transform |
| `ratio` | float/string | 0.3 | Portion of each word to bold (0.1–0.5 recommended) |
| `format` | string | "markdown" | Output format (see below) |

### Output Formats

| Format value | Bold syntax | Use when |
|-------------|------------|----------|
| `"markdown"` | `**bold**` | Terminal output, Slack, Discord, GTD tasks, any markdown-rendered surface |
| `"html"` | `<b>bold</b>` | Web surfaces (LiveView, email), Rich Text editors, any HTML context |

**Choose by destination:** if the consumer renders markdown, use `"markdown"`. If it renders HTML, use `"html"`. The transformation is identical — only the wrapping syntax changes.

### Response

```json
{
  "ok": true,
  "text": "**The** **qui**ck **bro**wn **fox** **jum**ps **ove**r **the** **laz**y **dog**",
  "stats": {"words": 9, "bolded": 9, "ratio": 0.3}
}
```

### Examples by bot

| Bot | Format | Reason |
|-----|--------|--------|
| Synapse (Discord) | `"markdown"` | Discord renders `**bold**` |
| GTD bot | `"markdown"` | TUI + bridge responses are markdown |
| Job Applications LiveView | `"html"` | Phoenix LiveView renders HTML |
| Email notifications | `"html"` | Email clients render HTML |
| LLM prompts | `"markdown"` | LLM output is markdown-native |