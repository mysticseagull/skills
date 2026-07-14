---
name: with-scripts
description: "Use this skill to <do a task backed by a helper script>. Trigger when the user asks to <action>, <action>, or <keyword>. Bundles a script the agent runs instead of reconstructing the logic each time."
---

# <Skill Title>

Guidance plus a bundled script. Prefer running the script over regenerating the same logic inline — it's tested and deterministic.

## When to Use

Activate when the user wants to <task>.

## How to Use

1. Read the inputs the script needs from the user's request.
2. Run the bundled helper:
   ```bash
   scripts/example.sh <arg1> <arg2>
   ```
3. Interpret the output and report back.

## Files

| Path | Purpose |
|---|---|
| `scripts/example.sh` | <what it does> |

## Guardrails

- Review the script's output before acting on it.
- The script must not be run with <dangerous inputs> — validate first.
