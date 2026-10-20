#!/usr/bin/env bash
# status.sh — list the repo's worktrees: branch, path, dirty state, Sail stack
# state, app URL and claimed port offset.
#
# Usage: status.sh
# Run from anywhere inside the repo. Read-only.
#
# stdout is a friendly table on a terminal; otherwise one line per worktree:
#   WORKTREE role=main|linked branch=... path=... dirty=yes|no
#            stack=running|stopped|n/a url=... offset=...
# Omitted keys mean empty/not applicable (url/offset are linked-worktree only).

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

MAIN_PATH=$(find_main_project_path)
cd "$MAIN_PATH"

# One docker call lists every running compose project (and doubles as the availability probe).
have_docker=no running=""
if command -v docker >/dev/null && running=$(docker ps --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null); then
    have_docker=yes
fi

rows=()
while read -r path branch; do
    role=linked; [[ "$path" == "$MAIN_PATH" ]] && role=main
    dirty=no; [[ -n "$(git -C "$path" status --porcelain)" ]] && dirty=yes

    stack=n/a url="" offset=""
    project=$(env_get COMPOSE_PROJECT_NAME "$path/.env")
    if [[ "$role" == linked ]]; then
        offset=$(claimed_offset "$branch")
        if [[ -n "$project" ]]; then
            url=$(env_get APP_URL "$path/.env")
            if [[ "$have_docker" == yes ]]; then
                if grep -qxF "$project" <<<"$running"; then
                    stack=running
                else
                    stack=stopped
                fi
            fi
        fi
    fi
    rows+=("$role|$branch|$path|$dirty|$stack|$url|$offset")
done < <(list_worktrees)

if [[ -t 1 ]]; then
    init_colors 1
    short() { echo "${1/#$HOME/\~}"; }
    linked=0
    printf '%s%-28s %-8s %-9s %-24s %s%s\n' "$C_BOLD" BRANCH CHANGES DOCKER APP LOCATION "$C_RESET"
    for row in "${rows[@]}"; do
        IFS='|' read -r role branch path dirty stack url offset <<<"$row"
        [[ "$role" == linked ]] && linked=$((linked + 1))
        changes="${C_GREEN}clean${C_RESET}   "; [[ "$dirty" == yes ]] && changes="${C_YELLOW}dirty${C_RESET}   "
        case "$stack" in
            running) docker="${C_GREEN}running${C_RESET}  " ;;
            stopped) docker="${C_DIM}stopped${C_RESET}  " ;;
            *)       docker="${C_DIM}-${C_RESET}        " ;;
        esac
        label="$branch"; [[ "$role" == main ]] && label="$branch (main project)"
        printf '%-28s %s %s %-24s %s\n' "$label" "$changes" "$docker" "${url:--}" "$(short "$path")"
    done
    if [[ "$linked" -eq 0 ]]; then
        printf '\nNo extra worktrees yet. Create one with: %s/up.sh <branch>\n' "$SCRIPT_DIR"
    else
        printf '\n%s linked worktree(s). Remove one with: %s/down.sh <branch>\n' "$linked" "$SCRIPT_DIR"
    fi
    printf 'New worktrees are created in %s  (change with up.sh --dir, WT_DIR, or: git config worktrees.dir <path>)\n' "$(short "$(worktrees_dir)")"
else
    for row in "${rows[@]}"; do
        IFS='|' read -r role branch path dirty stack url offset <<<"$row"
        line="WORKTREE role=$role branch=$branch path=$path dirty=$dirty stack=$stack"
        [[ -n "$url" ]] && line+=" url=$url"
        [[ -n "$offset" ]] && line+=" offset=$offset"
        echo "$line"
    done
fi
