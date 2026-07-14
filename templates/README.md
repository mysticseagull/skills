# Skill Templates

Copy-ready starting points for new skills. Pick the pattern that fits, then fill in the placeholders (`<...>`).

Use the scaffolding script from the repo root — it copies the template and sets the `name:` field to match the new folder. Run it with no arguments to be walked through picking a template and naming the skill:

```bash
./new-skill.sh                       # interactive: choose a template, enter a name
./new-skill.sh full my-new-skill     # or pass them directly
```

The new skill is created in your current directory by default; pass a third argument to place it elsewhere. On Windows, use the batch equivalent the same way: `new-skill.bat` (interactive) or `new-skill.bat full my-new-skill`.

Or copy a folder by hand with `cp -r` — just remember the `name` in `SKILL.md` must match the skill's folder name.

## Templates

| Template | Use it for | Structure |
|---|---|---|
| [`minimal/`](minimal/SKILL.md) | Simple, self-contained guidance — a handful of rules and an example. | `SKILL.md` only |
| [`with-references/`](with-references/SKILL.md) | Larger skills where detail lives in loaded-on-demand guides. | `SKILL.md` + `references/` |
| [`workflow/`](workflow/SKILL.md) | A repeatable step-by-step procedure with verification. | `SKILL.md` only |
| [`with-scripts/`](with-scripts/SKILL.md) | Tasks backed by a bundled, tested helper script. | `SKILL.md` + `scripts/` |
| [`full/`](full/SKILL.md) | Rich skills needing both explained rules and a tested helper. | `SKILL.md` + `references/` + `scripts/` |

## Writing a good `description`

The `description` is what the agent matches against to decide whether to activate the skill, so make it specific:

- **Name the triggers** — the concrete things the user says or does ("commit staged changes", "open a PR").
- **State the coverage** — what the skill actually knows how to do.
- **Draw the boundary** — where it stops, so it doesn't fire on unrelated tasks.

Vague (`"Helps with git"`) loses to specific (`"Trigger when the user asks to commit, branch, stash, or open a PR; covers commit format, branch naming, and history edits."`).

## Tips

- Keep `SKILL.md` lean — it's always in context. Push depth into `references/`.
- Write guidance as instructions ("Prefer X over Y"), not prose.
- Give concrete defaults so the agent doesn't have to guess.
- Include at least one worked example.
