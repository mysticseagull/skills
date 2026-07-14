---
name: git
description: "Use this skill for git workflows so commits, branches, stashes, pull requests, and history edits stay consistent. Trigger when the user asks to commit staged changes, write a commit message, run /commit, create or name a branch, stash or restore work, open a pull request, or rebase/amend/squash history. Covers conventional commit format, branch naming, stash management, PR titles/descriptions, and safe history rewriting."
---

# Git

Consistent git workflows: conventional commits, branch naming, stashing, pull requests, and safe history edits. Each topic has a detailed reference under `references/`.

## When to Use

Activate this skill whenever the user works with git — committing, branching, stashing, opening PRs, or rewriting history. Read the matching reference below before acting.

## References

| Topic | Guide | Use when |
|---|---|---|
| Commits | `references/git-commits-guide.md` | Writing a commit message or running `/commit` |
| Branches | `references/git-branches-guide.md` | Creating, naming, switching, or cleaning up branches |
| Stashes | `references/git-stash-guide.md` | Shelving and restoring uncommitted work |
| Pull requests | `references/git-pull-requests-guide.md` | Opening a PR with a consistent title/description |
| Rebase & history | `references/git-rebase-guide.md` | Rebasing, amending, or squashing commits |

## Quick Reference

- **Commits** follow `<type>(<scope>): <description>` — imperative, under ~72 chars.
- **Branches** use `type/short-description` (e.g. `feat/password-reset`). Never commit directly to `main`.
- **Stashes** are newest-first (`stash@{0}`); use `-u` to include untracked files.
- **PR titles** mirror the commit convention; reference issues with `Closes #123`.
- **History** is only safe to rewrite while it's local/unshared. Interactive flags (`git rebase -i`, `git add -i`) are **not supported** in this environment — use `--autosquash` with prepared `--fixup` commits.

## Guardrails

- Only commit, push, or open a PR when the user asks.
- Prefer `git switch`/`git restore` over the older `git checkout` for clarity.
- Use `git push --force-with-lease` (never plain `--force`) when a force-push is unavoidable.
