---
name: full
description: "Use this skill for <domain> that needs both explained rules and a tested helper. Trigger when the user asks to <action A>, <action B>, or <keyword>. Covers <topic 1> and <topic 2>; read the matching reference before acting and run the bundled script instead of reconstructing its logic."
---

# <Skill Title>

The full pattern: lean always-on guidance, deep `references/` loaded on demand, and `scripts/` for tested, deterministic work. Keep this file short — pull detail and logic out of it.

## When to Use

Activate when the user works with <domain>. Read the matching reference before acting; run the helper for the mechanical steps.

## How to Use

1. Read the request and identify which topic applies (see References).
2. Read the matching reference guide before acting.
3. Run the bundled helper for the deterministic part:
   ```bash
   scripts/example.sh <arg1> <arg2>
   ```
4. Interpret the output, apply the reference's rules, and report back.

## References

| Topic | Guide | Use when |
|---|---|---|
| <Topic 1> | `references/topic-1-guide.md` | <situation> |
| <Topic 2> | `references/topic-2-guide.md` | <situation> |

## Scripts

| Path | Purpose |
|---|---|
| `scripts/example.sh` | <what it does> |

## Quick Reference

- **<Topic 1>** — the one-line rule worth having in context always.
- **<Topic 2>** — the other always-on rule.

## Guardrails

- Review the script's output before acting on it.
- Stop and ask before <irreversible / outward-facing action>.
- Only act when the user asks.
