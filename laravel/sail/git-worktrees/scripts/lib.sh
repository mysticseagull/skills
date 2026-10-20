#!/usr/bin/env bash
# lib.sh — shared helpers and the step-pipeline engine for the git-worktrees
# scripts. Sourced by up.sh, down.sh and status.sh; not run directly.
#
# Output contract
#   Agent / pipe mode (stderr is not a terminal — the default for agents):
#     stdout  machine-readable KEY=value lines only (empty values omitted).
#     stderr  silent on success; "error: ..." / "warning: ..." lines otherwise.
#   Human mode (stderr is a terminal, or WT_PROGRESS=1; WT_PROGRESS=0 forces
#   agent mode): friendly progress, a labelled summary and "✖"/"⚠" messages on
#   stderr, in color unless NO_COLOR is set. The KEY=value lines are not printed
#   when stdout is itself a terminal (pipe to `cat` to get them).
#   Third-party tool output (git/docker/composer/npm) goes to $LOG, or streams
#   live with -v/--verbose (WT_VERBOSE=1).
#
# Pipeline
#   steps/NN-<name>.sh each define step_<name>_up and, optionally,
#   step_<name>_down and step_<name>_check (a dash in <name> becomes "_").
#   `up` runs steps in NN order; `down` runs them in reverse. Before either,
#   every selected step's _check runs (PHASE says which), so nothing is
#   changed if a check fails.
#   Steps share state through global variables and must be idempotent, so any
#   one can be re-run alone with --only. A step that doesn't apply calls
#   `skip "reason"` and returns.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEPS_DIR="$SCRIPT_DIR/steps"

if [[ "${WT_PROGRESS:-}" == 1 || ( "${WT_PROGRESS:-}" != 0 && -t 2 ) ]]; then
    WT_HUMAN=yes
else
    WT_HUMAN=no
fi
[[ "${WT_VERBOSE:-}" == 1 ]] && WT_VERBOSE=yes
WT_VERBOSE="${WT_VERBOSE:-no}"

ONLY="" FROM="" SKIP="" DRY_RUN=no LIST=no
CURRENT_STEP="" PHASE="" RETRY_HINT=no
CTX_VARS=""   # set by up.sh/down.sh; dumped under -v

# --- output ---------------------------------------------------------------

# init_colors FD — set C_* escapes if FD is a terminal and NO_COLOR is unset.
init_colors() {
    C_RED="" C_GREEN="" C_YELLOW="" C_DIM="" C_BOLD="" C_RESET=""
    if [[ -t "$1" && -z "${NO_COLOR:-}" ]]; then
        C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
        C_DIM=$'\e[2m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
    fi
}
init_colors 2

# Progress line, humans only.
progress() {
    if [[ "$WT_HUMAN" == yes ]]; then printf '%s→%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2; fi
}

# Final line or indented detail, humans only.
say() {
    if [[ "$WT_HUMAN" == yes ]]; then printf '%s\n' "$*" >&2; fi
}

# ok MESSAGE — green check line, humans only.
ok() {
    say "${C_GREEN}✔${C_RESET} ${C_BOLD}$*${C_RESET}"
}

# kv LABEL VALUE — aligned summary row, humans only.
kv() {
    if [[ "$WT_HUMAN" == yes ]]; then printf '  %s%-14s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2" >&2; fi
}

# Debug trace, only under -v.
trace() {
    if [[ "$WT_VERBOSE" == yes ]]; then printf '· %s\n' "$*" >&2; fi
}

# Marks the current step as not applicable.
skip() {
    trace "skip $CURRENT_STEP: $*"
}

# warn MESSAGE — non-fatal problem; always shown.
warn() {
    if [[ "$WT_HUMAN" == yes ]]; then
        printf '%s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
    else
        echo "warning: $*" >&2
    fi
}

# die MESSAGE — prints the error and exits 1.
die() {
    if [[ "$WT_HUMAN" == yes ]]; then
        printf '%s✖%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
    else
        echo "error: $*" >&2
    fi
    exit 1
}

# Prints KEY=value for each named shell variable that is non-empty (the
# scripts' stdout contract — an omitted key means empty/not applicable).
# Skipped on a terminal, where the human summary has already been shown.
emit() {
    local key
    [[ -t 1 ]] && return 0
    for key in "$@"; do
        [[ -n "${!key}" ]] && printf '%s=%s\n' "$key" "${!key}"
    done
    return 0
}

# --- running commands -----------------------------------------------------

# Runs a command with output appended to $LOG (callers set LOG=$(mktemp)), or
# also streamed live under -v. Returns the command's status.
try_logged() {
    if [[ "$WT_VERBOSE" == yes ]]; then
        trace "\$ $*"
        "$@" 2>&1 | tee -a "$LOG" >&2
    else
        "$@" >>"$LOG" 2>&1
    fi
}

# try_logged, but on failure prints the command, the log's tail and the log
# path, then exits.
run_logged() {
    local rc=0
    try_logged "$@" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        RETRY_HINT=yes
        if [[ "$WT_HUMAN" == yes ]]; then
            printf '%s✖%s %s failed (exit %s)\n' "$C_RED" "$C_RESET" "$*" "$rc" >&2
            [[ "$WT_VERBOSE" == yes ]] || tail -n 20 "$LOG" | sed "s/^/    ${C_DIM}│${C_RESET} /" >&2
            printf '  Full log: %s\n' "$LOG" >&2
        else
            echo "error: command failed ($rc): $*" >&2
            [[ "$WT_VERBOSE" == yes ]] || tail -n 20 "$LOG" >&2
            echo "full log: $LOG" >&2
        fi
        exit 1
    fi
}

# --- .env / project helpers -----------------------------------------------

# Portable `sed -i` across GNU sed (Linux) and BSD sed (macOS).
sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# env_get KEY [FILE] — prints KEY's last value in FILE (default .env), or nothing.
env_get() {
    grep "^$1=" "${2:-.env}" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# env_set KEY VALUE [FILE] — replaces KEY's line in FILE (default .env), or appends it.
env_set() {
    local file="${3:-.env}"
    if grep -q "^$1=" "$file"; then
        sed_inplace "s|^$1=.*|$1=$2|" "$file"
    else
        echo "$1=$2" >> "$file"
    fi
}

# Absolute path of the main working tree (first entry of `git worktree list`).
find_main_project_path() {
    git worktree list --porcelain | awk '/^worktree /{print $2; exit}'
}

# Name of the compose file in cwd, in `docker compose`'s own lookup order; returns 1 if none.
find_compose_file() {
    local f
    for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        [[ -f "$f" ]] && echo "$f" && return 0
    done
    return 1
}

# declared_package_manager [DIR] — the manager named by package.json's
# "packageManager" field (npm|yarn|pnpm), or nothing.
declared_package_manager() {
    sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\(npm\|yarn\|pnpm\)@.*/\1/p' "${1:-.}/package.json" 2>/dev/null | head -1
}

# node_lockfiles [DIR] — the Node lockfiles present in DIR, one per line.
node_lockfiles() {
    local f
    for f in package-lock.json yarn.lock pnpm-lock.yaml; do
        [[ -f "${1:-.}/$f" ]] && echo "$f"
    done
    return 0
}

# find_node_package_manager [DIR] — the Node package manager DIR (default cwd)
# uses: the "packageManager" field if set, else its lockfile (yarn, then pnpm,
# then npm if several are present — callers warn about that), else npm.
find_node_package_manager() {
    local declared
    declared=$(declared_package_manager "${1:-.}")
    if [[ -n "$declared" ]]; then
        echo "$declared"
    elif [[ -f "${1:-.}/yarn.lock" ]]; then
        echo yarn
    elif [[ -f "${1:-.}/pnpm-lock.yaml" ]]; then
        echo pnpm
    else
        echo npm
    fi
}

# The main checkout's current branch (empty if detached).
current_branch() {
    git -C "$MAIN_PATH" branch --show-current
}

# worktrees_dir [FLAG_VALUE] — absolute path of the folder worktrees are created
# in. First match wins: the --dir flag value, $WT_DIR, `git config worktrees.dir`
# (repo-local, set with `git config worktrees.dir <path>`), then .gitworktrees.
# Relative paths are taken from the main checkout; a leading ~ is expanded.
worktrees_dir() {
    local dir="${1:-${WT_DIR:-}}"
    [[ -n "$dir" ]] || dir=$(git -C "$MAIN_PATH" config --get worktrees.dir || true)
    dir="${dir:-.gitworktrees}"
    dir="${dir/#\~/$HOME}"
    [[ "$dir" == /* ]] || dir="$MAIN_PATH/$dir"
    realpath -m "$dir"
}

# slugify TEXT — lowercase, anything outside a-z0-9 becomes "-".
slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-'
}

# list_worktrees — prints "<path> <branch>" per worktree, main checkout first
# ("(detached)" when there is no branch).
list_worktrees() {
    git worktree list --porcelain | awk '
        /^worktree /{p=$2; b="(detached)"} /^branch /{b=$2; sub("refs/heads/","",b)} /^$/{print p, b}'
}

# resolve_worktree TARGET — TARGET is a branch name or a worktree path. Sets
# WORKTREE_PATH and BRANCH (either may be the main checkout; callers exclude it).
# Returns 1 if nothing matches.
resolve_worktree() {
    local target="$1" abs wt_path wt_branch
    abs=$(realpath -m "$target")
    while read -r wt_path wt_branch; do
        if [[ "$wt_path" == "$abs" || "$wt_branch" == "$target" ]]; then
            WORKTREE_PATH="$wt_path"
            BRANCH="$wt_branch"
            return 0
        fi
    done < <(list_worktrees)
    return 1
}

# compose_port_vars FILE — prints "VAR default" for each host-forwarded port
# variable in the compose file's ports: blocks, e.g. `- '${APP_PORT:-80}:80'`
# -> "APP_PORT 80" (default empty if the compose file gives none).
compose_port_vars() {
    local in_ports=no line seen=" "
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*ports:[[:space:]]*$ ]]; then
            in_ports=yes
        elif [[ "$in_ports" == yes ]]; then
            if [[ ! "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                in_ports=no
            elif [[ "$line" =~ \$\{([A-Z_]+)(:-([0-9]+))?\} ]]; then
                [[ "$seen" == *" ${BASH_REMATCH[1]} "* ]] && continue
                seen+="${BASH_REMATCH[1]} "
                echo "${BASH_REMATCH[1]} ${BASH_REMATCH[3]}"
            fi
        fi
    done < "$1"
}

# --- host port allocation ---------------------------------------------------
# Offsets are multiples of 10 added to every host-forwarded port. A probe of
# currently-bound ports can't see a sibling worktree whose stack is stopped, so
# claimed offsets are also recorded in a registry (one "<offset> <branch>" line
# each) in the repo's git dir, and a lock serialises allocation between
# parallel up.sh runs. Needs MAIN_PATH.

ports_registry() {
    echo "$(cd "$MAIN_PATH" && realpath "$(git rev-parse --git-common-dir)")/worktree-ports"
}

port_in_use() {
    (echo > "/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# claimed_offset BRANCH — prints BRANCH's claimed offset, or nothing.
claimed_offset() {
    awk -v b="$1" '$2 == b {print $1}' "$(ports_registry)" 2>/dev/null | tail -1 || true
}

release_offset() {
    local file
    file=$(ports_registry)
    [[ -f "$file" ]] || return 0
    awk -v b="$1" '$2 != b' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

claim_offset() {
    release_offset "$1"
    echo "$2 $1" >> "$(ports_registry)"
}

# find_free_offset BRANCH PORT... — prints the lowest offset (10..500) that no
# other branch has claimed and at which none of the PORTs+offset is bound.
find_free_offset() {
    local branch="$1" claimed attempt candidate port conflict
    shift
    claimed=$(awk -v b="$branch" '$2 != b {print $1}' "$(ports_registry)" 2>/dev/null || true)
    for attempt in $(seq 1 50); do
        candidate=$((attempt * 10))
        grep -qx "$candidate" <<<"$claimed" && continue
        conflict=no
        for port in "$@"; do
            port_in_use $((port + candidate)) && { conflict=yes; break; }
        done
        [[ "$conflict" == no ]] && { echo "$candidate"; return 0; }
    done
    return 1
}

# allocate_offset BRANCH PORT... — find_free_offset, then claim it.
allocate_offset() {
    local offset
    offset=$(find_free_offset "$@") || return 1
    claim_offset "$1" "$offset"
    echo "$offset"
}

# with_registry_lock CMD... — runs CMD while holding the registry lock.
with_registry_lock() {
    local lock tries=0 rc=0
    lock="$(ports_registry).lock"
    until mkdir "$lock" 2>/dev/null; do
        tries=$((tries + 1))
        [[ "$tries" -le 100 ]] || die "timed out waiting for the port registry lock ($lock) — remove it if no other up.sh is running"
        sleep 0.1
    done
    "$@" || rc=$?
    rmdir "$lock"
    return "$rc"
}

# sail / artisan in the current directory, per MODE (sail|plain).
sail() { ./vendor/bin/sail "$@"; }
artisan() {
    if [[ "$MODE" == sail ]]; then sail artisan "$@"; else php artisan "$@"; fi
}

# --- pipeline engine --------------------------------------------------------

# step_enabled ID — whether --only/--skip leave step ID in the run (ignores --from).
step_enabled() {
    [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]] && [[ ",$SKIP," != *",$1,"* ]]
}

# parse_common_flag "$@" — handles the debug flags shared by up.sh and down.sh.
# Returns 0 and sets COMMON_SHIFT (args consumed) if $1 was one of them.
parse_common_flag() {
    case "$1" in
        --only) ONLY="${2:-}"; COMMON_SHIFT=2 ;;
        --from) FROM="${2:-}"; COMMON_SHIFT=2 ;;
        --skip) SKIP="${2:-}"; COMMON_SHIFT=2 ;;
        --dry-run) DRY_RUN=yes; COMMON_SHIFT=1 ;;
        --list) LIST=yes; COMMON_SHIFT=1 ;;
        -v|--verbose) WT_VERBOSE=yes; COMMON_SHIFT=1 ;;
        *) return 1 ;;
    esac
}

step_ids() {
    local f b
    for f in "$STEPS_DIR"/[0-9]*.sh; do
        b="${f##*/}"; b="${b#*-}"; echo "${b%.sh}"
    done
}

step_fn() { echo "step_${1//-/_}_$2"; }

load_steps() {
    local f
    for f in "$STEPS_DIR"/[0-9]*.sh; do source "$f"; done
}

# step_desc ID — the step's `# desc:` line.
step_desc() {
    sed -n 's/^# desc: //p' "$STEPS_DIR"/[0-9]*-"$1".sh
}

# Describes every step: which phases it implements and its `# desc:` line.
list_steps() {
    local id phases fn
    for id in $(step_ids); do
        phases=""
        for fn in up check down; do
            declare -F "$(step_fn "$id" "$fn")" >/dev/null && phases+="$fn "
        done
        printf '%-10s %-14s %s\n' "$id" "$phases" "$(step_desc "$id")"
    done
}

# Prints the step ids to run for a phase, in execution order, after applying
# --only / --from / --skip. Unknown names are an error.
plan_steps() {
    local phase="$1" all=() ordered=() id name
    for id in $(step_ids); do all+=("$id"); done
    for name in ${ONLY//,/ } ${SKIP//,/ } ${FROM:-}; do
        [[ " ${all[*]} " == *" $name "* ]] || die "unknown step '$name' (known: ${all[*]})"
    done

    if [[ "$phase" == down ]]; then
        for ((i = ${#all[@]} - 1; i >= 0; i--)); do ordered+=("${all[i]}"); done
    else
        ordered=("${all[@]}")
    fi

    local started=yes
    [[ -n "$FROM" ]] && started=no
    for id in "${ordered[@]}"; do
        [[ "$id" == "$FROM" ]] && started=yes
        [[ "$started" == yes ]] || continue
        step_enabled "$id" || continue
        echo "$id"
    done
}

dump_ctx() {
    local v
    for v in $CTX_VARS; do printf '  %s=%s\n' "$v" "${!v-}" >&2; done
}

# Printed on any non-zero exit that happened inside a step.
on_exit() {
    local rc=$? args
    # Only after a failed command — validation errors (die) say what to fix instead.
    if [[ "$rc" -ne 0 && "$RETRY_HINT" == yes && -n "$CURRENT_STEP" ]]; then
        args=$(sed -E 's/--(only|from|skip) [^ ]+//g; s/(^| )(-v|--verbose|--dry-run)( |$)/ /g' <<<"${ORIG_ARGS:-}" | tr -s ' ')
        if [[ "$WT_HUMAN" == yes ]]; then
            printf '\n  Stopped at the "%s" step. Nothing after it ran. To retry just that step:\n    %s%s %s --only %s -v%s\n' \
                "$CURRENT_STEP" "$C_DIM" "$(basename "$0")" "$args" "$CURRENT_STEP" "$C_RESET" >&2
        else
            echo "failed in step '$CURRENT_STEP' — retry just that step: $(basename "$0") $args --only $CURRENT_STEP -v" >&2
        fi
        [[ "$WT_VERBOSE" == yes ]] && { echo "context:" >&2; dump_ctx; }
    fi
}

# pipeline_run up|down — runs the selected steps. Each step starts in the main
# project root; steps cd into the worktree themselves where they need to.
pipeline_run() {
    local phase="$1" id fn n=0 started total
    local selected=()
    PHASE="$phase"
    while IFS= read -r id; do selected+=("$id"); done < <(plan_steps "$phase")
    total=${#selected[@]}

    if [[ "$DRY_RUN" == yes ]]; then
        if [[ "$WT_HUMAN" == yes ]]; then
            echo "Dry run — nothing will change. Steps for '$phase', in order:" >&2
            for id in "${selected[@]}"; do
                printf '  %-10s %s\n' "$id" "$(step_desc "$id")" >&2
            done
        else
            for id in "${selected[@]}"; do
                declare -F "$(step_fn "$id" check)" >/dev/null && echo "would check: $id" >&2
                declare -F "$(step_fn "$id" "$phase")" >/dev/null && echo "would run: $id ($phase)" >&2
            done
        fi
        return 0
    fi

    trap on_exit EXIT
    for id in "${selected[@]}"; do
        fn=$(step_fn "$id" check)
        if declare -F "$fn" >/dev/null; then
            CURRENT_STEP="$id"; cd "$MAIN_PATH"; trace "check $id"; "$fn"
        fi
    done

    for id in "${selected[@]}"; do
        n=$((n + 1))
        fn=$(step_fn "$id" "$phase")
        declare -F "$fn" >/dev/null || continue
        CURRENT_STEP="$id"; cd "$MAIN_PATH"
        trace "[$n/$total] $id ($phase)"
        started=$SECONDS
        "$fn"
        trace "done $id in $((SECONDS - started))s"
    done
    CURRENT_STEP=""
    if [[ "$WT_VERBOSE" == yes ]]; then echo "context:" >&2; dump_ctx; fi
}
