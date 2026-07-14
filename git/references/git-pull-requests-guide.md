# Git Pull Requests Guide

Open pull requests with titles and descriptions that mirror the commit conventions.

## Prerequisites

- Use the `gh` CLI for GitHub operations.
- The branch must be pushed with an upstream (`git push -u origin <branch>`).

## Title Format

Follow the same convention as commit subjects (see `git-commits-guide.md`):

```
<type>(<scope>): <description>
```

Example: `feat(auth): add password reset functionality`

## Description Structure

Keep it focused on *what* changed and *why*:

```
## Summary
- Bullet points describing the change

## Testing
- How the change was verified (tests run, manual checks)

## Notes
- Anything reviewers should know (follow-ups, trade-offs)
```

Reference related issues in the body so they auto-close on merge: `Closes #123`.

## Common Workflow

1. Push the branch:
   ```
   git push -u origin feat/password-reset
   ```
2. Create the PR:
   ```
   gh pr create --title "feat(auth): add password reset" --body "..."
   ```
3. Check status and reviews:
   ```
   gh pr status
   gh pr view --web
   ```

## Guardrails

- Only push or open a PR when the user asks.
- Keep PRs small and scoped to one branch/change.
- Make sure tests pass before requesting review.
