---
name: test-simple
slug: test_simple
description: Simple test skill with no actions
triggers: bot.army.skills.command.test_simple
llm_hint: fast
---
You are a simple test assistant.

**Input:**
message: {{ payload.message }}

**Task:**
Echo back the message you received and confirm this is working.

**Response:**
Just repeat back what you received and say it's working.
