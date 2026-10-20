---
name: git-worktrees
description: Use when the user wants to work on a Laravel branch in an isolated git worktree (own Sail stack, ports, and .env), spin off parallel work, check on existing worktrees, or tear one down when the work is done
license: MIT
tags:
  - laravel
  - sail
  - docker
  - worktree
  - git
---

# Laravel Worktrees

Isolated git worktree per branch. If the project uses Laravel Sail, the worktree gets its own Docker stack, offset host ports, and `.env`, so it runs alongside the main checkout. Without Sail it's a plain worktree with `.env` copied and host installs.

Works unattended (subagent) or in the main chat. Decide, don't ask — state what you chose.

Scripts live in this skill's `scripts/` directory; call them by full path. They can run from anywhere inside the repo.

## Start

If the user refers to an existing worktree, or the branch may already exist, `scripts/status.sh` lists worktrees (branch, dirty, stack, URL, port offset). Otherwise just run `up.sh` — it reuses an existing worktree.

```bash
scripts/up.sh <branch> [--base <ref>] [--dir <path>] [--no-push] [--migrate] [--seed] [--no-install] [--rebuild]
```

- **Branch:** use the name the user gave verbatim; otherwise infer a short kebab-case one from the task (match the repo's prefix convention). Ask only if the task gives nothing to go on.
- **Base:** defaults to the main checkout's current branch. Pass `--base` only if the user names one.
- **Location:** worktrees go in `.gitworktrees/` inside the project (hidden from `git status` via the repo-local exclude). If the user names another folder, pass `--dir <path>`; for a lasting choice they can run `git config worktrees.dir <path>` (or set `WT_DIR`). Relative paths are from the project root.
- **Push:** the branch is pushed to origin by default, so work isn't stranded in a local worktree. Pass `--no-push` for a quick spin-off that will merge straight back into the current branch, or when the task says to keep it local. No origin, or a failed push, just warns and continues local-only.
- **`--migrate` / `--seed`:** decide from the task — pass them when the work needs a database in a known state. Both are off by default.
- **`--no-install`:** when only reading code or the deps are irrelevant. Under Sail the app won't boot without `vendor/`, so don't use it if the app needs to run.
- **`--rebuild`:** rebuild the Sail image even if cached — only when the branch changes the Dockerfile.
- **Package manager:** `packageManager` in `package.json`, else the lockfile. If `up.sh` warns that several lockfiles exist, tell the user which one it used.

Agents get `KEY=value` lines on stdout only (empty keys omitted) and `error:`/`warning:` lines on stderr; people at a terminal get friendly progress, a labelled summary and no `KEY=value` dump. Keys: `MODE` (`sail`|`plain`), `BRANCH`, `BASE` (omitted when the branch already existed), `WORKTREE_PATH`, `APP_URL`, `VITE_PORT`, `PKG_MANAGER`, `DEV_COMMAND`, `PUSHED`/`MIGRATED`/`SEEDED`. On failure it prints the log tail and exits non-zero; see `references/troubleshooting.md`.

**The dev server is not started.** Run `DEV_COMMAND` yourself if the task needs it, or use a full build instead. In sail mode `DEV_COMMAND` already carries the worktree's port flags and the right argument form for the package manager — run it as printed; don't add `--host` or edit `vite.config.*`.

## Work

All work happens in `WORKTREE_PATH` — read/edit files there, run git there, and run artisan/tests/pint through *that* worktree's `./vendor/bin/sail` (sail mode) or the host binaries (plain mode). Never edit the main checkout.

**Commit as you go.** Make a commit at each meaningful milestone — a working increment, a passing test, a finished refactor — not one big commit at the end. Describe what changed and why, in the repo's existing style (`git log --oneline -10`). Stage deliberately (`git add <paths>`), keeping `.env` and generated files out. Commit and push only `<branch>`; if `PUSHED=yes`, run `git push origin <branch>` after each commit so the work survives the session. `down.sh` refuses to clean up uncommitted changes or unmerged, unpushed commits, so finishing fully committed makes teardown one command.

Tell the user (and any subagent): the worktree path, and in sail mode the app URL.

## Finish

When the work is complete, remove everything unless the user said to keep something:

```bash
scripts/down.sh <branch|worktree-path> [--keep-branch] [--keep-volumes] [--remote|--keep-remote] [--force]
```

Removes the Docker stack and its volumes (`--keep-volumes` keeps the database), the worktree, and the local branch, and releases the worktree's port offset. It refuses (changing nothing) if the worktree is dirty or the branch has commits that are neither merged nor pushed. Don't add `--force` on your own — it discards work; confirm with the user first. The branch on origin is deleted automatically only if it's already merged into the current branch (the spin-off case); a pushed-but-unmerged branch is kept since it may back a PR. `--remote` deletes it regardless and `--keep-remote` never does — use either only when the user says so.

Integrating the branch (merge, PR) is the user's own workflow and out of scope.

## Debugging

A failed run names the failing step and prints the exact retry command (`--only <step> -v`). Flags and internals: `references/debugging.md`.

## References

- `references/troubleshooting.md` — read only when a script fails or the site misbehaves (ports, white page, 401, Vite, vendor).
- `references/debugging.md` — step pipeline flags, port registry, adding steps, tests.
