#!/usr/bin/env bash
# create-worktree.sh — create (or reuse) an isolated git worktree for a branch,
# forked explicitly from a known base branch, and push it immediately.
#
# Usage: create-worktree.sh <branch-name> <base-branch>
# Run from the main project's root. <base-branch> should come from
# detect-base-branch.sh — this script does not guess at one.
#
# Prints KEY=value lines to stdout:
#   SITE_NAME       sanitized folder name used under .worktrees/
#   WORKTREE_PATH   relative path to the created worktree

set -euo pipefail

branch_name="${1:-}"
base_branch="${2:-}"

if [[ -z "$branch_name" || -z "$base_branch" ]]; then
    echo "usage: create-worktree.sh <branch-name> <base-branch>" >&2
    exit 1
fi

project_name=$(basename "$PWD")
sanitized_branch_name=$(echo "$branch_name" | tr '/' '-')
site_name="${project_name}--${sanitized_branch_name}"
worktree_path=".worktrees/${site_name}"

# Make sure the base branch itself is up to date before forking from it.
git fetch origin "$base_branch"

if git worktree list | grep -qF "[${branch_name}]"; then
    echo "Worktree for $branch_name already exists at $worktree_path — reusing it." >&2
elif git show-ref --verify --quiet "refs/heads/$branch_name"; then
    # Branch already exists locally but isn't attached to any worktree right now
    # (e.g. a prior worktree for it was removed without deleting the branch) —
    # attach it to a new worktree rather than trying to create it again.
    git worktree add "$worktree_path" "$branch_name"
else
    git worktree add "$worktree_path" -b "$branch_name" "origin/$base_branch"
fi

# Push immediately so the branch exists remotely and isn't stranded locally
# if the session ends before "Finishing Work" ever runs.
(
    cd "$worktree_path"
    git push -u origin "$branch_name"
)

cat <<EOF
SITE_NAME=$site_name
WORKTREE_PATH=$worktree_path
EOF
