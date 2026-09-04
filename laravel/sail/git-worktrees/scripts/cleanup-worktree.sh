#!/usr/bin/env bash
# cleanup-worktree.sh — tear down a worktree's Sail stack and remove the
# worktree directory. Never touches the branch itself.
#
# Usage: cleanup-worktree.sh <worktree-path>
# Run from the main project's root.
#
# Deleting, merging, or rebasing the branch is deliberately not this script's
# job — that's left for the user to do themselves, on purpose. The branch and
# its commits (local and, since create-worktree.sh pushes immediately, remote)
# are untouched by this script; only the worktree checkout goes away.

set -euo pipefail

worktree_path="${1:-}"

if [[ -z "$worktree_path" ]]; then
    echo "usage: cleanup-worktree.sh <worktree-path>" >&2
    exit 1
fi

if [[ -x "$worktree_path/vendor/bin/sail" ]]; then
    (cd "$worktree_path" && ./vendor/bin/sail down --volumes)
fi

git worktree remove "$worktree_path"
