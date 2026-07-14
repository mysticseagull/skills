---
name: workflow
description: "Use this skill to <perform a multi-step procedure> reliably. Trigger when the user asks to <run the process>, <the process by name>, or <the outcome they want>. Walks through <the procedure> step by step and verifies the result."
---

# <Procedure Name>

A repeatable, step-by-step procedure for <goal>. Follow the steps in order; do not skip verification.

## When to Use

Activate when the user wants to <run the procedure>. Confirm scope first if <ambiguous condition>.

## Steps

1. **<First step>** — what to do and what "done" looks like.
2. **<Second step>** — the next action. Note any command:
   ```bash
   <command to run>
   ```
3. **<Third step>** — continue the sequence.
4. **Verify** — how to confirm the procedure actually worked (run the flow, check the output, not just "it should work").

## Guardrails

- Stop and ask the user before <irreversible / outward-facing action>.
- If <a step fails>, do <the recovery action> rather than pressing on.

## Done When

- <Observable success condition 1>.
- <Observable success condition 2>.
