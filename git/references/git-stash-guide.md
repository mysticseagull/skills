# Git Stash Guide

Temporarily shelve uncommitted changes so you can switch context, then restore them later.

## When to Use

- You need to switch branches but aren't ready to commit.
- You want to pull/rebase on a dirty working tree.
- You want to test a clean state without losing your work.

## Common Workflow

1. Stash the current changes (with a message):
   ```
   git stash push -m "wip: password reset form"
   ```
2. Do the other work (switch branches, pull, etc.).
3. Restore the changes:
   ```
   git stash pop        # re-apply the latest stash and remove it
   ```

## Include Untracked Files

By default, stash ignores untracked and ignored files. To include them:

```
git stash push -u -m "wip"     # include untracked files
git stash push -a -m "wip"     # include untracked AND ignored files
```

## Apply vs Pop

- `git stash pop` — re-applies the stash and **removes** it from the stash list.
- `git stash apply` — re-applies the stash but **keeps** it (useful to apply to multiple branches).

## Useful Commands

| Command | Purpose |
|---|---|
| `git stash list` | List all stashes |
| `git stash show -p stash@{0}` | Show the diff of a stash |
| `git stash push -m "msg"` | Stash tracked changes with a message |
| `git stash push -u -m "msg"` | Also stash untracked files |
| `git stash pop` | Apply the latest stash and drop it |
| `git stash apply stash@{1}` | Apply a specific stash, keep it |
| `git stash drop stash@{0}` | Delete a specific stash |
| `git stash clear` | Delete all stashes |

## Gotchas

- Stashes are referenced newest-first: `stash@{0}` is the most recent.
- `git stash clear` is irreversible — there's no undo.
- A `pop` that hits a merge conflict does **not** drop the stash; resolve the conflict, then `git stash drop` manually.
