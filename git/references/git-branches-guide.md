# Git Branches Guide

Create and manage branches with consistent naming and a clean workflow.

## Naming Convention

Use a `type/short-description` slug, lowercase with dashes:

- `feat/password-reset`
- `fix/login-redirect`
- `docs/api-examples`
- `refactor/user-service`
- `test/auth-coverage`
- `chore/bump-deps`

The `type` prefix matches the commit types (see `git-commits-guide.md`).

## Common Workflow

1. Start from an up-to-date base branch:
   ```
   git switch main
   git pull
   ```
2. Create and switch to the new branch:
   ```
   git switch -c feat/password-reset
   ```
3. Do the work, commit, and push with upstream tracking:
   ```
   git push -u origin feat/password-reset
   ```

## Guardrails

- Never commit directly to `main`. If you started work on `main` by mistake, move it to a branch:
  ```
  git switch -c feat/password-reset   # carries uncommitted changes with you
  ```
- Keep branches short-lived and focused on one change.
- Delete merged branches to keep the list clean:
  ```
  git branch -d feat/password-reset          # local
  git push origin --delete feat/password-reset   # remote
  ```

## Useful Commands

| Command | Purpose |
|---|---|
| `git branch` | List local branches |
| `git branch -a` | List local + remote branches |
| `git switch <name>` | Switch to an existing branch |
| `git switch -c <name>` | Create and switch to a new branch |
| `git branch -m <new-name>` | Rename the current branch |
| `git branch -d <name>` | Delete a merged branch |
| `git branch -D <name>` | Force-delete an unmerged branch |
