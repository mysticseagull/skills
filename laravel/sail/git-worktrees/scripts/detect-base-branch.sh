#!/usr/bin/env bash
# detect-base-branch.sh — figure out which branch a new worktree branch should
# fork from, based on this repo's branching strategy and this branch's own
# naming convention.
#
# Usage: detect-base-branch.sh <branch-name>
# Run from the main project's root, before creating the worktree.
#
# Checks origin for exactly two things: an integration branch (develop or
# development) and a trunk branch (main or master). If an integration branch
# exists, that's normally the base (git-flow strategy); otherwise the trunk is
# (trunk-based). One exception: a hotfix-style branch name (hotfix/, fix/,
# bugfix/, patch/, or a fix: prefix) always bases off the trunk directly, even
# under git-flow — that's the standard convention for patching what's already
# released, bypassing the integration branch.
#
# Prints KEY=value lines to stdout:
#   STRATEGY                    git-flow | trunk
#   DEFAULT_BRANCH               origin's trunk branch (main or master)
#   INTEGRATION_BRANCH           origin's integration branch (develop or
#                                 development), or empty if it has none
#   IS_HOTFIX                    yes|no — whether <branch-name> matched a
#                                 hotfix-style naming convention
#   BASE_BRANCH                  the computed answer
#   CONVENTIONAL_COMMITS         yes|no — unrelated to branching strategy,
#                                 just a cheap signal for commit message style
#   NEEDS_CONFIRMATION           yes|no
#   NEEDS_CONFIRMATION_REASON    human-readable reason, or empty
#
# Always exits 0 — NEEDS_CONFIRMATION is the signal, not a nonzero exit.

set -uo pipefail

branch_name="${1:-}"
if [[ -z "$branch_name" ]]; then
    echo "usage: detect-base-branch.sh <branch-name>" >&2
    exit 1
fi

needs_confirmation=no
needs_confirmation_reason=""

# --- trunk: main or master ---
default_branch=""
for candidate in main master; do
    if git show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
        default_branch="$candidate"
        break
    fi
done

if [[ -z "$default_branch" ]]; then
    needs_confirmation=yes
    needs_confirmation_reason="neither 'main' nor 'master' found on origin"
fi

# --- integration branch: develop or development ---
integration_matches=""
for candidate in develop development; do
    if git show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
        integration_matches="$integration_matches $candidate"
    fi
done
integration_matches="${integration_matches# }"

if [[ "$integration_matches" == *" "* ]]; then
    needs_confirmation=yes
    needs_confirmation_reason="both develop and development exist on origin — unclear which is the real integration branch"
fi

integration_branch="${integration_matches%% *}"

# --- strategy ---
if [[ -n "$integration_branch" ]]; then
    strategy=git-flow
else
    strategy=trunk
fi

# --- hotfix-style naming convention: widen this list if the repo uses
#     something else (e.g. "chore/", team-specific prefixes) ---
is_hotfix=no
case "$branch_name" in
    hotfix/*|hotfix-*|fix/*|fix:*|bugfix/*|patch/*) is_hotfix=yes ;;
esac

# --- base branch: hotfix-style branches skip the integration branch ---
if [[ "$strategy" == git-flow && "$is_hotfix" == no ]]; then
    base_branch="$integration_branch"
else
    base_branch="$default_branch"
fi

# --- Conventional Commits / semantic-release signal (unrelated to branching) ---
conventional_commits=no
for f in commitlint.config.js commitlint.config.cjs .releaserc .releaserc.json .releaserc.yml release.config.js; do
    [[ -f "$f" ]] && conventional_commits=yes && break
done

cat <<EOF
STRATEGY=$strategy
DEFAULT_BRANCH=$default_branch
INTEGRATION_BRANCH=$integration_branch
IS_HOTFIX=$is_hotfix
BASE_BRANCH=$base_branch
CONVENTIONAL_COMMITS=$conventional_commits
NEEDS_CONFIRMATION=$needs_confirmation
NEEDS_CONFIRMATION_REASON=$needs_confirmation_reason
EOF
