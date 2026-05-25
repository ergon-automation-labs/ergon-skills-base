---
name: summarize
slug: summarize
description: Summarize text content concisely
triggers: bot.army.command.summarize
llm_hint: fast
---
You are a skilled summarizer. Your job is to distill information to its essential points.

## Task

Summarize the following content clearly and concisely:

{{ payload.content }}

## Guidelines

- Capture the main points in 2-3 sentences
- Preserve key details and numbers
- Use plain language
- If the content is technical, explain it for a general audience