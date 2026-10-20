#!/usr/bin/env bash
# up.sh — create a git worktree for a branch and, if the project uses Laravel
# Sail, bring up its own isolated Sail stack.
#
# Usage: up.sh <branch> [options]
# Run from anywhere inside the repo (main checkout or an existing worktree).
#
#   --base <ref>    branch to fork from (default: the main checkout's current branch)
#   --dir <path>    folder to create worktrees in (relative to the main checkout, or
#                   absolute). Default .gitworktrees; set it persistently with
#                   `git config worktrees.dir <path>` or the WT_DIR environment variable.
#   --no-push       keep the branch local. Default is to push it to origin with
#                   upstream tracking; skip for a quick spin-off that merges
#                   straight back. No origin or a failed push just warns.
#   --migrate       run `artisan migrate`
#   --seed          run `artisan db:seed`
#   --no-install    skip composer/node installs (under Sail the app won't boot without vendor/)
#   --rebuild       rebuild the Sail image even if cached (e.g. Dockerfile changed)
#
# Debugging (shared with down.sh) — the work is a pipeline of steps/NN-*.sh:
#   --list          show the steps and exit
#   --only a,b      run just these steps       --skip a,b   run all but these
#   --from a        start at step a            --dry-run    show what would run
#   -v, --verbose   trace steps, stream command output live, dump context
#
# Sail is only used when the project actually has it (compose file plus a
# laravel/sail install in the main project). Otherwise the worktree is created
# and .env copied, with host composer/node installs when available.
#
# Prints KEY=value lines to stdout:
#   MODE            sail | plain
#   BRANCH, BASE    (BASE omitted when the branch or worktree already existed)
#   WORKTREE_PATH   absolute path — all further work happens here
#   APP_URL         sail mode only
#   VITE_PORT       sail mode only (omitted if the compose file has none)
#   PKG_MANAGER     yarn | pnpm | npm — package.json "packageManager", else lockfile
#   DEV_COMMAND     command to start the dev server (not started by this script)
#   PUSHED, MIGRATED, SEEDED   yes | no

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ORIG_ARGS="$*"
BRANCH="" BASE="" DIR_FLAG=""
load_steps   # step files own their variables' defaults; flags below override them

while [[ $# -gt 0 ]]; do
    if parse_common_flag "$@"; then shift "$COMMON_SHIFT"; continue; fi
    case "$1" in
        --base) BASE="${2:-}"; shift 2 ;;
        --dir) DIR_FLAG="${2:-}"; shift 2 ;;
        --no-push) DO_PUSH=no; shift ;;
        --migrate) DO_MIGRATE=yes; shift ;;
        --seed) DO_SEED=yes; shift ;;
        --no-install) DO_INSTALL=no; shift ;;
        --rebuild) REBUILD=yes; shift ;;
        -*) die "unknown option: $1" ;;
        *) BRANCH="$1"; shift ;;
    esac
done

if [[ "$LIST" == yes ]]; then list_steps; exit 0; fi
[[ -n "$BRANCH" ]] || die "Which branch? Usage: up.sh <branch> [--base <ref>] [--dir <path>] [--no-push] [--migrate] [--seed] [--no-install] [--rebuild]  (debug: --only|--skip|--from|--dry-run|--list|-v)"

MAIN_PATH=$(find_main_project_path)
cd "$MAIN_PATH"

if [[ -z "$BASE" ]]; then
    BASE=$(current_branch)
    [[ -n "$BASE" ]] || die "The main checkout is on a detached HEAD, so there's no branch to fork from. Pass --base <ref>."
fi

WORKTREES_DIR=$(worktrees_dir "$DIR_FLAG")
WORKTREE_PATH="$WORKTREES_DIR/$(basename "$MAIN_PATH")--${BRANCH//\//-}"

# Sail only when the project actually has it.
MODE=plain
if [[ -d "$MAIN_PATH/vendor/laravel/sail" ]] && find_compose_file >/dev/null; then
    MODE=sail
fi

LOG=$(mktemp)
CTX_VARS="MODE BRANCH BASE MAIN_PATH WORKTREES_DIR WORKTREE_PATH DO_PUSH DO_MIGRATE DO_SEED DO_INSTALL REBUILD"
say "Setting up a worktree for '$BRANCH' ($MODE mode)"
pipeline_run up
[[ "$DRY_RUN" == yes ]] && exit 0
rm -f "$LOG"

# --- summary ---
APP_URL="" VITE_PORT="" PKG_MANAGER=""
if [[ -d "$WORKTREE_PATH" ]]; then
    PKG_MANAGER=$(find_node_package_manager "$WORKTREE_PATH")
    DEV_COMMAND="$PKG_MANAGER run dev"
    if [[ "$MODE" == sail && -f "$WORKTREE_PATH/.env" ]]; then
        APP_URL="http://localhost:$(env_get APP_PORT "$WORKTREE_PATH/.env")"
        VITE_PORT=$(env_get VITE_PORT "$WORKTREE_PATH/.env")
        DEV_COMMAND="./vendor/bin/sail $PKG_MANAGER run dev"
        # npm needs "--" to forward flags; yarn and pnpm forward them directly (and yarn warns on "--").
        sep=" --"; [[ "$PKG_MANAGER" == npm ]] || sep=""
        [[ -n "$VITE_PORT" ]] && DEV_COMMAND+="$sep --port $VITE_PORT --strictPort"
    fi
fi

if [[ "$WT_HUMAN" == yes ]]; then
    where="local only"
    [[ "$PUSHED" == yes ]] && where="pushed to origin"
    source_note="existing branch"
    [[ -n "$BASE" ]] && source_note="from $BASE"
    ok "Worktree ready for '$BRANCH'"
    say ""
    kv Location "$WORKTREE_PATH"
    kv Branch "$BRANCH  ($source_note, $where)"
    [[ -n "$APP_URL" ]] && kv App "$APP_URL"
    [[ "$MIGRATED" == yes ]] && kv Database "migrated$([[ "$SEEDED" == yes ]] && echo ' and seeded')"
    [[ "$MIGRATED" != yes && "$SEEDED" == yes ]] && kv Database "seeded"
    say ""
    say "Next:"
    kv "Work in it" "cd $WORKTREE_PATH"
    kv "Dev server" "$DEV_COMMAND   ${C_DIM}(not started)${C_RESET}"
    kv "When done" "$SCRIPT_DIR/down.sh $BRANCH"
fi

emit MODE BRANCH BASE WORKTREE_PATH APP_URL VITE_PORT PKG_MANAGER DEV_COMMAND PUSHED MIGRATED SEEDED
