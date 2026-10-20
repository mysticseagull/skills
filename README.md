# Skills

A personal collection of custom [Agent Skills](https://agentskills.io) used across my projects. Each skill packages reusable guidance — conventions, workflows, and reference material — that an AI agent loads on demand when a task matches.

Skills follow the open [`SKILL.md`](https://agentskills.io) standard, so they work across any compatible agent — Claude Code, Cursor, GitHub Copilot, Windsurf, Gemini CLI, Cline, OpenCode, and more — and can be installed from the [skills.sh](https://skills.sh) directory.

## What's a skill?

A skill is a directory containing a `SKILL.md` file. The frontmatter tells the agent when to activate it; the body tells the agent how to behave once it does. Skills can bundle deeper reference docs (or scripts and templates) under a `references/` folder, which the agent reads only when the task calls for them.

```
skills/
└── <skill-name>/
    ├── SKILL.md            # frontmatter + guidance
    └── references/         # optional deep-dive docs
        └── *.md
```

`SKILL.md` frontmatter:

```yaml
---
name: git
description: >-
  Use this skill for ... Trigger when the user asks to ...
---
```

The `description` is the most important field — the agent reads it to decide whether the skill is relevant, so it should name concrete triggers (what the user says or does) and what the skill covers.

## Available skills

| Skill | What it does |
|-------|--------------|
| [`git`](git/SKILL.md) | Consistent git workflows — conventional commits, branch naming, stashing, pull requests, and safe history edits. Detailed guides live in [`git/references/`](git/references). |
| [`laravel/sail/git-worktrees`](laravel/sail/git-worktrees/SKILL.md) | One-command isolated Laravel worktree (own Sail stack, claimed port offsets, own `.env` when Sail is present; plain worktree otherwise), status, and one-command teardown. |

## Usage

Install a skill from this repo into your agent with a single command:

```bash
npx skills add <owner>/<repo>
```

This copies the skills into the location your agent discovers them (e.g. `.claude/skills/` for Claude Code, or the equivalent for Cursor, Copilot, Windsurf, Gemini CLI, Cline, or OpenCode). You can also install manually by copying (or symlinking) a skill directory into your agent's skills folder.

Once installed, the agent activates a skill automatically when a task matches its `description`. In agents that support it, you can also invoke one explicitly with `/<skill-name>`.

## Adding a skill

Scaffold from a [template](templates/) with the helper script, then fill in the placeholders. Run it with no arguments to be walked through choosing a template and naming the skill:

```bash
./new-skill.sh                       # interactive: pick a template, enter a name
./new-skill.sh full my-new-skill     # or pass them directly
```

The skill is created in your current directory (pass a third argument to change that). On Windows, use `new-skill.bat` the same way. Either form copies the chosen template and sets the `name:` field for you. Or do it by hand:

1. Create a directory named after the skill (kebab-case).
2. Add a `SKILL.md` with `name` and `description` frontmatter.
3. Write the guidance in the body; keep it focused and actionable.
4. Move any long-form detail into `references/*.md` and link to it from `SKILL.md`.
5. Add a row to the table above.
