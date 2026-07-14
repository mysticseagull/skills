---
name: with-references
description: "Use this skill for <domain> so <the thing> stays consistent. Trigger when the user asks to <action A>, <action B>, or <action C>. Covers <topic 1>, <topic 2>, and <topic 3>. Read the matching reference before acting."
---

# <Skill Title>

Short overview of the domain. Keep this file lean — it's always loaded. Push detail into `references/` so the agent only pulls it when needed.

## When to Use

Activate whenever the user works with <domain>. Read the matching reference below before acting.

## References

| Topic | Guide | Use when |
|---|---|---|
| <Topic 1> | `references/topic-1-guide.md` | <situation> |
| <Topic 2> | `references/topic-2-guide.md` | <situation> |

## Quick Reference

- **<Topic 1>** — the one-line rule worth having in context always.
- **<Topic 2>** — the other always-on rule.

## Guardrails

- A hard constraint the agent must never violate.
- Another safety rail (e.g. "only act when the user asks").
