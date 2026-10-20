#!/usr/bin/env bash
# down.sh — remove everything up.sh created for a branch: the Docker stack and
# its volumes, the worktree directory, and the local branch.
#
# Usage: down.sh <branch|worktree-path> [options]
# Run from anywhere inside the repo.
#
#   --keep-branch    leave the local branch in place
#   --keep-volumes   stop containers but keep the stack's volumes (DB data)
#   --remote         delete the branch on origin even if unmerged
#   --keep-remote    never delete the branch on origin
#   --force          remove a dirty worktree, and delete a branch that is neither
#                    merged nor fully pushed (that work is lost)
#
# By default the remote branch is deleted only if it's already merged into the
# current branch; a pushed-but-unmerged branch (maybe a PR) is kept.
#
# Debugging (shared with up.sh): --list, --only a,b, --skip a,b, --from a,
# --dry-run, -v/--verbose. Steps run in reverse of up.sh; every step's _check
# runs first, so a refusal changes nothing.
#
# Refuses (exit 1, nothing changed) if the worktree has uncommitted changes, or
# the branch has commits that exist nowhere else, unless --force is passed.
#
# Prints KEY=value lines to stdout:
#   BRANCH, WORKTREE_PATH
#   STACK_REMOVED, WORKTREE_REMOVED, BRANCH_DELETED, REMOTE_DELETED   yes | no

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ORIG_ARGS="$*"
target=""
load_steps   # step files own their variables' defaults; flags below override them

while [[ $# -gt 0 ]]; do
    if parse_common_flag "$@"; then shift "$COMMON_SHIFT"; continue; fi
    case "$1" in
        --keep-branch) KEEP_BRANCH=yes; shift ;;
        --keep-volumes) KEEP_VOLUMES=yes; shift ;;
        --remote) DELETE_REMOTE=yes; shift ;;
        --keep-remote) DELETE_REMOTE=no; shift ;;
        --force) FORCE_FLAG=--force; shift ;;
        -*) die "unknown option: $1" ;;
        *) target="$1"; shift ;;
    esac
done

if [[ "$LIST" == yes ]]; then list_steps; exit 0; fi
[[ -n "$target" ]] || die "Which worktree? Usage: down.sh <branch|worktree-path> [--keep-branch] [--keep-volumes] [--remote|--keep-remote] [--force]  (debug: --only|--skip|--from|--dry-run|--list|-v)"

MAIN_PATH=$(find_main_project_path)
cd "$MAIN_PATH"

resolve_worktree "$target" || true
[[ -n "$WORKTREE_PATH" && "$WORKTREE_PATH" != "$MAIN_PATH" ]] || die "No worktree found for '$target'. Run status.sh to see which exist."

LOG=$(mktemp)
CTX_VARS="BRANCH MAIN_PATH WORKTREE_PATH FORCE_FLAG KEEP_BRANCH KEEP_VOLUMES DELETE_REMOTE"
say "Removing the worktree for '$BRANCH'"
pipeline_run down
[[ "$DRY_RUN" == yes ]] && exit 0
rm -f "$LOG"

if [[ "$WT_HUMAN" == yes ]]; then
    if [[ "$STACK_REMOVED" == yes ]]; then
        stack="removed$([[ "$KEEP_VOLUMES" == no ]] && echo ', including its volumes')"
    else
        stack="nothing to remove"
    fi
    if [[ "$BRANCH_DELETED" == yes ]]; then
        local_branch="deleted"
    elif [[ "$KEEP_BRANCH" == yes ]]; then
        local_branch="kept (--keep-branch)"
    else
        local_branch="kept (it's checked out in the main project)"
    fi
    if [[ "$REMOTE_DELETED" == yes ]]; then
        remote_branch="deleted"
    elif [[ "$DELETE_REMOTE" == no ]]; then
        remote_branch="kept (--keep-remote)"
    elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
        remote_branch="kept — not merged into $(current_branch) yet"
    else
        remote_branch="not on origin"
    fi
    ok "Cleaned up '$BRANCH'"
    say ""
    kv "Docker stack" "$stack"
    kv Worktree "removed ($WORKTREE_PATH)"
    kv "Local branch" "$local_branch"
    kv "Origin branch" "$remote_branch"
fi

emit BRANCH WORKTREE_PATH STACK_REMOVED WORKTREE_REMOVED BRANCH_DELETED REMOTE_DELETED
