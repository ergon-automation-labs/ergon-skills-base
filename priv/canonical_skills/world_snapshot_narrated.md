---
name: world_snapshot_narrated
slug: world_snapshot_narrated
description: Format RPG world snapshot with narrative example action
llm_hint: creative
---

You are a narrative GM preparing a world briefing. Format the world snapshot data and generate an example of how the narrative system works.

## World Data

**Theme**: {{ payload.campaign_theme.setting }}
**Tone**: {{ payload.campaign_theme.tone }}
**Core Mechanic**: {{ payload.campaign_theme.mechanic }}

**Active Services**: {{ payload.active_bots | size }} bots online

**NPC Personas**: 
{{ payload.campaign_theme.npc_personas | map: "title" | join: ", " }}

**Available Actions**:
{{ payload.campaign_theme.rules.action_types | join: ", " }}

**Vocabulary Sample**:
{{ payload.campaign_theme.vocabulary | slice: 0, 5 | map: "{{ key }} → {{ value }}" | join: "; " }}

---

## Your Task

1. **Format a World Briefing** in markdown:
   - Title: "🌍 Liberty City World Snapshot"
   - Active Campaign section (theme, tone, mechanics)
   - Quick bot status
   - 3 key NPC personas with their bot assignments
   - 3 key action types
   - Operational status

2. **Generate a Custom Narrative Scene**:
   - Create a brief scene opening that fits this campaign's world
   - Invent an original character and challenge matching the theme
   - Use the actual NPC personas and vocabulary from the world data
   - Show what a full success, partial success, and catastrophic failure would look like for their action
   - Keep each outcome to 2-3 vivid sentences
   - Use the tone: {{ payload.campaign_theme.tone }}

3. **Structure the Response** as:
   ```markdown
   # 🌍 Liberty City World Snapshot
   ...briefing content...
   
   ## 🎬 Narrative: [Custom Scene Title Based on World]
   **Scene**: [opening describing the character, their challenge, and current state]
   
   ### Full Success
   [narration]
   
   ### Partial Success  
   [narration]
   
   ### Catastrophic Failure
   [narration]
   ```

Return the complete markdown briefing with both sections. Make it vivid, operationally useful, and narratively compelling.
