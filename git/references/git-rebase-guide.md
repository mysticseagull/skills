# Git Rebase & History Guide

Keep a clean, linear history and tidy up commits before sharing them.

## Harness Caveat

Interactive flags are **not supported** in this environment:

- `git rebase -i` and `git add -i` will not work here.

Use the non-interactive alternatives below (`--autosquash` with prepared fixup commits, or `git commit --amend`).

## Golden Rule

**Never rewrite history that has been shared.** Rebasing, amending, or squashing commits that others have already pulled forces everyone else into conflict resolution. Only rewrite commits that live solely on your local, un-pushed (or un-reviewed) branch.

## Update a Branch onto the Latest Base

Bring your branch up to date with `main` without a merge commit:

```
git switch feat/password-reset
git fetch origin
git rebase origin/main
```

Resolve conflicts as they appear, then:

```
git add <resolved-files>
git rebase --continue
```

Abort and return to the pre-rebase state at any time:

```
git rebase --abort
```

## Amend the Last Commit

Fix the most recent commit (message or forgotten files) before pushing:

```
git add <files>
git commit --amend
```

## Squash with Prepared Fixups (non-interactive)

Since `-i` is unavailable, create fixup commits and let rebase fold them automatically:

```
git commit --fixup <target-commit-sha>
git rebase --autosquash origin/main
```

`--autosquash` reorders and marks the `fixup!` commits so they merge into their targets without an interactive editor.

## Force-Push Safely

After rewriting local history, update the remote branch with a lease so you don't clobber others' work:

```
git push --force-with-lease
```

Prefer `--force-with-lease` over `--force`: it refuses to overwrite if the remote has commits you haven't seen.
