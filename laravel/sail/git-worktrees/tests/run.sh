#!/usr/bin/env bash
# tests/run.sh — dependency-free tests for the git-worktrees scripts.
#
# Usage: tests/run.sh [name-filter]
#
# Each t_* function runs in a subshell inside a fresh throwaway repo. Sail mode
# is simulated with a stubbed vendor/laravel/sail and --skip bootstrap,stack,deps,
# so no Docker is needed. Exits non-zero if any assertion failed.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$SKILL_DIR/scripts"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export WT_PROGRESS=0 WT_VERBOSE=0
SAIL_SKIPS="bootstrap,stack,deps"

ROOT=$(mktemp -d)
LISTENERS=()
cleanup() {
    local pid
    for pid in ${LISTENERS[@]+"${LISTENERS[@]}"}; do kill "$pid" 2>/dev/null; done
    rm -rf "$ROOT"
}
trap cleanup EXIT

# --- assertions: print "ok - desc" / "not ok - desc" -------------------------
assert() {
    local desc="$1"; shift
    if "$@"; then echo "ok - $desc"; else echo "not ok - $desc"; fi
}
contains() { [[ "$1" == *"$2"* ]]; }
refute() { ! "$@"; }
exists() { [[ -e "$1" ]]; }
eq() { [[ "$1" == "$2" ]]; }

# new_repo [sail] — makes $ROOT/N/proj with a compose file and one commit, cd's
# into it. Base ports are random so tests don't collide with real services.
new_repo() {
    local dir="$ROOT/$RANDOM$RANDOM/proj"
    mkdir -p "$dir" && cd "$dir" || exit 1
    BASE_PORT=$((20000 + RANDOM % 20000))
    git init -q -b main
    cat > compose.yaml <<COMPOSE
services:
    laravel.test:
        ports:
            - '\${APP_PORT:-$BASE_PORT}:80'
            - '\${VITE_PORT:-$((BASE_PORT + 1))}:\${VITE_PORT:-$((BASE_PORT + 1))}'
    mysql:
        ports:
            - '\${FORWARD_DB_PORT:-$((BASE_PORT + 2))}:3306'
COMPOSE
    printf 'APP_URL=http://localhost\nDB_PORT=3306\nSANCTUM_STATEFUL_DOMAINS=a.test\n' > .env
    printf '.env\nvendor/\n' > .gitignore
    git add -A 2>/dev/null && git commit -qm init
    if [[ "${1:-}" == sail ]]; then
        mkdir -p vendor/laravel/sail/bin && echo '#!/bin/sh' > vendor/laravel/sail/bin/sail
    fi
    REPO="$PWD"
}

wt_dir() { echo "${WT_ROOT:-$REPO/.gitworktrees}/proj--${1//\//-}"; }
up()   { "$S/up.sh" "$@" 2>&1; }

# tty_run CMD... — runs CMD attached to a pseudo-terminal (stdout and stderr
# are terminals, as for a person at a shell) and prints what it displayed.
tty_run() {
    python3 - "$@" <<'PY'
import os, pty, subprocess, sys
master, slave = pty.openpty()
env = {k: v for k, v in os.environ.items() if k != "WT_PROGRESS"}
p = subprocess.Popen(sys.argv[1:], env=env, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
out = b""
while True:
    try:
        chunk = os.read(master, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
p.wait()
sys.stdout.write(out.decode().replace("\r", ""))
PY
}
down() { "$S/down.sh" "$@" 2>&1; }
registry() { cat "$(git rev-parse --git-common-dir)/worktree-ports" 2>/dev/null; }

# with_origin — adds a bare origin and pushes main.
with_origin() {
    git init -q --bare "$ROOT/origin-$RANDOM.git" 2>/dev/null
    local o; o=$(ls -dt "$ROOT"/origin-*.git | head -1)
    git remote add origin "$o"; git push -q origin main 2>/dev/null
    ORIGIN="$o"
}
on_origin() { git --git-dir="$ORIGIN" show-ref --verify --quiet "refs/heads/$1"; }

# --- tests ------------------------------------------------------------------

t_list() {
    new_repo
    local out; out=$("$S/up.sh" --list)
    local step
    for step in preflight worktree remote bootstrap env stack deps database; do
        assert "--list shows $step" contains "$out" "$step"
    done
}

t_plain_cycle() {
    new_repo
    local out; out=$("$S/up.sh" feat/a --no-install 2>/dev/null)
    assert "mode plain" contains "$out" "MODE=plain"
    assert "worktree created" exists "$(wt_dir feat/a)/.git"
    assert "branch created" git show-ref --verify --quiet refs/heads/feat/a
    assert "default folder is .gitworktrees" exists "$REPO/.gitworktrees/proj--feat-a/.git"
    assert "folder excluded from status" grep -qx '/.gitworktrees/' "$(git rev-parse --git-common-dir)/info/exclude"
    assert "main checkout stays clean" eq "$(git status --porcelain)" ""
    assert "stdout is only KEY=value" refute grep -qvE '^[A-Z_]+=' <<<"$out"
    assert "empty keys omitted" refute contains "$out" "APP_URL="
    assert "not pushed by default" contains "$out" "PUSHED=no"
    out=$("$S/up.sh" feat/a --no-install 2>/dev/null); assert "rerun succeeds" eq $? 0
    assert "reused worktree reports no fork point" refute contains "$out" "BASE="
    out=$("$S/down.sh" feat/a 2>/dev/null)
    assert "down reports removal" contains "$out" "WORKTREE_REMOVED=yes"
    assert "worktree gone" refute exists "$(wt_dir feat/a)"
    assert "branch gone" refute git show-ref --verify --quiet refs/heads/feat/a
}

t_push_defaults() {
    new_repo; with_origin
    local out
    out=$("$S/up.sh" feat/a --no-install 2>/dev/null)
    assert "pushes by default" contains "$out" "PUSHED=yes"
    assert "branch is on origin" on_origin feat/a
    out=$("$S/up.sh" feat/b --no-install --no-push 2>/dev/null)
    assert "--no-push stays local" contains "$out" "PUSHED=no"
    assert "--no-push not on origin" refute on_origin feat/b
    new_repo
    out=$("$S/up.sh" feat/d --no-install 2>/dev/null)
    assert "no origin continues local-only" contains "$out" "PUSHED=no"
    assert "no origin still creates worktree" exists "$(wt_dir feat/d)/.git"
}

t_push_failure_warns() {
    new_repo; git remote add origin "$ROOT/does-not-exist.git"
    local out; out=$(up feat/a --no-install)
    assert "warns instead of failing" contains "$out" "warning: Couldn't push"
    assert "worktree still created" exists "$(wt_dir feat/a)/.git"
}

t_remote_teardown() {
    new_repo; with_origin
    # spin-off merged straight back: remote branch deleted automatically
    up feat/a --no-install >/dev/null
    git -C "$(wt_dir feat/a)" commit -q --allow-empty -m work
    git -C "$(wt_dir feat/a)" push -q origin feat/a 2>/dev/null
    git merge -q feat/a
    local out; out=$("$S/down.sh" feat/a 2>/dev/null)
    assert "merged remote branch deleted" contains "$out" "REMOTE_DELETED=yes"
    assert "gone from origin" refute on_origin feat/a
    # pushed but unmerged: kept by default (may back a PR)
    up feat/b --no-install >/dev/null
    git -C "$(wt_dir feat/b)" commit -q --allow-empty -m work
    git -C "$(wt_dir feat/b)" push -q origin feat/b 2>/dev/null
    out=$("$S/down.sh" feat/b 2>/dev/null)
    assert "unmerged remote kept" refute contains "$out" "REMOTE_DELETED=yes"
    assert "still on origin" on_origin feat/b
    # explicit overrides
    up feat/c --no-install >/dev/null
    git -C "$(wt_dir feat/c)" commit -q --allow-empty -m work
    git -C "$(wt_dir feat/c)" push -q origin feat/c 2>/dev/null
    down feat/c --remote >/dev/null
    assert "--remote deletes unmerged" refute on_origin feat/c
    up feat/d --no-install >/dev/null; git merge -q feat/d 2>/dev/null
    down feat/d --keep-remote >/dev/null
    assert "--keep-remote keeps merged" on_origin feat/d
}

t_human_output() {
    command -v python3 >/dev/null || { echo "ok - skipped (no python3)"; return; }
    new_repo; with_origin
    export NO_COLOR=1
    local out; out=$(tty_run "$S/up.sh" feat/h --no-install)
    assert "up: friendly headline" contains "$out" "Worktree ready for 'feat/h'"
    assert "up: shows location" contains "$out" "Location"
    assert "up: says where the branch went" contains "$out" "from main, pushed to origin"
    assert "up: points at next steps" contains "$out" "When done"
    assert "up: no raw KEY=value dump on a terminal" refute contains "$out" "WORKTREE_PATH="
    assert "up: no ANSI codes with NO_COLOR" refute contains "$out" $'\e['

    out=$(tty_run "$S/status.sh")
    assert "status: header" contains "$out" "BRANCH"
    assert "status: marks the main project" contains "$out" "main (main project)"
    assert "status: lists the worktree" contains "$out" "feat/h"
    assert "status: footer" contains "$out" "1 linked worktree(s)"
    assert "status: says where worktrees live" contains "$out" "New worktrees are created in"
    assert "status: shows the default folder" contains "$out" ".gitworktrees"

    out=$(tty_run "$S/down.sh" feat/h)
    assert "down: friendly headline" contains "$out" "Cleaned up 'feat/h'"
    assert "down: itemised" contains "$out" "Local branch   deleted"
    assert "down: remote row" contains "$out" "Origin branch"

    out=$(tty_run "$S/up.sh" 'bad..name')
    assert "errors use the ✖ form" contains "$out" "✖"
    assert "errors suggest a fix" contains "$out" "Try something like"
    out=$(tty_run "$S/up.sh" feat/x --only worktree --base nope)
    assert "validation errors get no retry hint" refute contains "$(tty_run "$S/up.sh" "bad..name")" "To retry"
    assert "failure explains how to retry" contains "$out" "To retry just that step"
    unset NO_COLOR
    new_repo
    out=$(tty_run "$S/status.sh")
    assert "status: empty state" contains "$out" "No extra worktrees yet"
}

t_worktrees_dir() {
    new_repo
    local out
    out=$("$S/up.sh" feat/a --no-install --dir custom/trees 2>/dev/null)
    assert "--dir relative to project root" exists "$REPO/custom/trees/proj--feat-a/.git"
    assert "inside-repo dir excluded" grep -qx '/custom/trees/' "$(git rev-parse --git-common-dir)/info/exclude"
    assert "WORKTREE_PATH reports it" contains "$out" "WORKTREE_PATH=$REPO/custom/trees/proj--feat-a"

    WT_DIR="$ROOT/by-env" "$S/up.sh" feat/b --no-install >/dev/null 2>&1
    assert "WT_DIR env var" exists "$ROOT/by-env/proj--feat-b/.git"
    assert "outside-repo dir not excluded" refute grep -q "by-env" "$(git rev-parse --git-common-dir)/info/exclude"

    git config worktrees.dir "$ROOT/by-config"
    "$S/up.sh" feat/c --no-install >/dev/null 2>&1
    assert "git config worktrees.dir" exists "$ROOT/by-config/proj--feat-c/.git"

    WT_DIR="$ROOT/by-env" "$S/up.sh" feat/d --no-install >/dev/null 2>&1
    assert "env beats git config" exists "$ROOT/by-env/proj--feat-d/.git"
    WT_DIR="$ROOT/by-env" "$S/up.sh" feat/e --no-install --dir "$ROOT/by-flag" >/dev/null 2>&1
    assert "flag beats env" exists "$ROOT/by-flag/proj--feat-e/.git"

    out=$("$S/down.sh" feat/a 2>&1); assert "down finds worktrees in any folder" contains "$out" "WORKTREE_REMOVED=yes"
    touch README.md
    out=$(up feat/f --no-install --dir README.md)
    assert "file as folder rejected" contains "$out" "isn't a folder"
    out=$(up feat/g --dir .)
    assert "project root as folder rejected" contains "$out" "can't be the project root"
}

t_dry_run() {
    new_repo
    local out; out=$(up feat/d --dry-run)
    assert "dry-run lists steps" contains "$out" "would run: worktree (up)"
    assert "dry-run lists checks" contains "$out" "would check: preflight"
    assert "dry-run creates nothing" refute exists "$(wt_dir feat/d)"
}

t_preflight() {
    new_repo
    local out
    out=$(up 'bad..name'); assert "invalid branch rejected" contains "$out" "not a valid git branch name"
    out=$(up feat/x --base nope); assert "unknown base rejected" contains "$out" "doesn't resolve"
    assert "nothing created" refute exists "$(wt_dir feat/x)"
    git branch -q other; git worktree add -q "$REPO/.gitworktrees/elsewhere" other
    out=$(up other --no-install)
    assert "branch checked out elsewhere rejected" contains "$out" "already checked out at"
    git branch -q kept; out=$("$S/up.sh" kept --no-install 2>/dev/null)
    assert "existing branch reports no fork point" refute contains "$out" "BASE="
    assert "existing branch is attached" exists "$(wt_dir kept)/.git"
}

t_failure_hint() {
    new_repo
    local out; out=$(up feat/f --only worktree --base nope)
    assert "names the failed step" contains "$out" "failed in step 'worktree'"
    assert "gives retry command" contains "$out" "--only worktree -v"
    assert "no duplicate --only" refute contains "$out" "--only worktree --only"
    assert "keeps the log path" contains "$out" "full log:"
}

t_down_guards() {
    new_repo
    up feat/a --no-install >/dev/null
    local w; w=$(wt_dir feat/a)
    echo x > "$w/f.txt"
    local out; out=$(down feat/a)
    assert "dirty refused" contains "$out" "uncommitted changes"
    assert "dirty refusal changes nothing" exists "$w"
    rm "$w/f.txt"
    git -C "$w" commit -q --allow-empty -m wip
    out=$(down feat/a)
    assert "unmerged refused" contains "$out" "neither merged"
    assert "unmerged refusal changes nothing" exists "$w"
    out=$(down feat/a --keep-branch --skip stack)
    assert "--keep-branch removes worktree" refute exists "$w"
    assert "--keep-branch keeps branch" git show-ref --verify --quiet refs/heads/feat/a
    up feat/b --no-install >/dev/null
    git -C "$(wt_dir feat/b)" commit -q --allow-empty -m wip
    down feat/b --force >/dev/null
    assert "--force deletes unmerged" refute git show-ref --verify --quiet refs/heads/feat/b
    up feat/c --no-install >/dev/null
    git -C "$(wt_dir feat/c)" commit -q --allow-empty -m wip; git merge -q feat/c
    down feat/c >/dev/null
    assert "merged branch removed" refute git show-ref --verify --quiet refs/heads/feat/c
}

t_ports_registry() {
    new_repo sail
    up feat/a --skip $SAIL_SKIPS >/dev/null
    local env_a; env_a="$(wt_dir feat/a)/.env"
    assert "first worktree offset 10" eq "$(grep ^APP_PORT= "$env_a" | cut -d= -f2)" $((BASE_PORT + 10))
    assert "APP_URL points at it" contains "$(cat "$env_a")" "APP_URL=http://localhost:$((BASE_PORT + 10))"
    assert "internal DB_PORT untouched" contains "$(cat "$env_a")" "DB_PORT=3306"
    assert "sanctum extended" contains "$(cat "$env_a")" "SANCTUM_STATEFUL_DOMAINS=a.test,localhost:$((BASE_PORT + 10))"
    assert "own session cookie" contains "$(cat "$env_a")" "SESSION_COOKIE=proj--feat-a_session"
    assert "project name pinned" contains "$(cat "$env_a")" "COMPOSE_PROJECT_NAME=proj--feat-a"
    assert "claim recorded" contains "$(registry)" "10 feat/a"

    up feat/b --skip $SAIL_SKIPS >/dev/null
    assert "cookies differ per worktree" contains "$(cat "$(wt_dir feat/b)/.env")" "SESSION_COOKIE=proj--feat-b_session"
    assert "stopped sibling's ports not reused" eq "$(grep ^APP_PORT= "$(wt_dir feat/b)/.env" | cut -d= -f2)" $((BASE_PORT + 20))

    down feat/a --skip stack >/dev/null
    assert "down releases claim" refute contains "$(registry)" "feat/a"
    up feat/c --skip $SAIL_SKIPS >/dev/null
    assert "released offset reused" eq "$(grep ^APP_PORT= "$(wt_dir feat/c)/.env" | cut -d= -f2)" $((BASE_PORT + 10))

    local before; before=$(cat "$(wt_dir feat/c)/.env")
    up feat/c --only env >/dev/null
    assert "env step idempotent" eq "$(cat "$(wt_dir feat/c)/.env")" "$before"

    sed -i '/^COMPOSE_PROJECT_NAME=/d' "$(wt_dir feat/c)/.env"
    up feat/c --only env >/dev/null
    assert "forced re-probe doesn't compound offsets" eq "$(grep ^APP_PORT= "$(wt_dir feat/c)/.env" | cut -d= -f2)" $((BASE_PORT + 10))
}

t_port_probe() {
    command -v python3 >/dev/null || { echo "ok - skipped (no python3)"; return; }
    new_repo sail
    python3 -c "
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', $((BASE_PORT + 10)))); s.listen(); time.sleep(30)" &
    local pid=$!
    sleep 0.5
    up feat/a --skip $SAIL_SKIPS >/dev/null
    kill $pid 2>/dev/null
    assert "bound port skipped" eq "$(grep ^APP_PORT= "$(wt_dir feat/a)/.env" | cut -d= -f2)" $((BASE_PORT + 20))
}

t_parallel_env() {
    new_repo sail
    local b
    for b in a b c d; do up feat/$b --skip $SAIL_SKIPS,env >/dev/null; done
    for b in a b c d; do up feat/$b --only env >/dev/null & done
    wait
    local ports; ports=$(for b in a b c d; do grep ^APP_PORT= "$(wt_dir feat/$b)/.env"; done | sort -u | wc -l)
    assert "parallel allocations are distinct" eq "$ports" 4
    assert "lock released" refute exists "$(git rev-parse --git-common-dir)/worktree-ports.lock"
}

t_status() {
    new_repo sail
    up feat/a --skip $SAIL_SKIPS >/dev/null
    local out; out=$("$S/status.sh" | cat)
    assert "lists main" contains "$out" "role=main branch=main"
    assert "lists linked worktree" contains "$out" "role=linked branch=feat/a"
    assert "shows offset" contains "$out" "offset=10"
    assert "shows url" contains "$out" "url=http://localhost:$((BASE_PORT + 10))"
}

# stub_pm — puts fake npm/yarn/pnpm on PATH that log "<name> <args>" to $PM_LOG
# and succeed, except that `npm ci` fails when $ROOT/fail-ci exists.
stub_pm() {
    PM_LOG="$ROOT/pm-$RANDOM.log"; : > "$PM_LOG"
    mkdir -p "$ROOT/bin"
    local pm
    for pm in npm yarn pnpm; do
        cat > "$ROOT/bin/$pm" <<STUB
#!/usr/bin/env bash
echo "$pm \$*" >> "$PM_LOG"
[[ "$pm \$1" == "npm ci" && -e "$ROOT/fail-ci" ]] && exit 1
exit 0
STUB
        chmod +x "$ROOT/bin/$pm"
    done
    export PATH="$ROOT/bin:$PATH"
}

t_node_install() {
    new_repo
    echo '{}' > package.json; echo '{}' > package-lock.json
    git add -A; git commit -qm node
    stub_pm
    up feat/a >/dev/null
    assert "npm ci used with a lockfile" eq "$(cat "$PM_LOG")" "npm ci"
    assert "worktree stays clean" eq "$(git -C "$(wt_dir feat/a)" status --porcelain)" ""

    # drifted lockfile: ci fails, fall back to install with a warning
    : > "$PM_LOG"; touch "$ROOT/fail-ci"
    local out; out=$(up feat/b)
    assert "falls back to install" eq "$(tr '\n' ',' < "$PM_LOG")" "npm ci,npm install,"
    assert "fallback warns" contains "$out" "out of sync with package.json"
    rm "$ROOT/fail-ci"
}

t_package_manager_choice() {
    new_repo
    echo '{}' > package.json; echo '{}' > package-lock.json; echo '{}' > yarn.lock
    git add -A; git commit -qm both
    stub_pm
    local out; out=$(up feat/a)
    assert "conflicting lockfiles warn" contains "$out" "Found package-lock.json and yarn.lock — using yarn"
    assert "falls back to lockfile order" contains "$(cat "$PM_LOG")" "yarn install --frozen-lockfile"

    echo '{"packageManager": "npm@10.8.0"}' > package.json; git commit -qam declare
    : > "$PM_LOG"; out=$(up feat/b)
    assert "packageManager field wins" eq "$(cat "$PM_LOG")" "npm ci"
    assert "no warning once declared" refute contains "$out" "Found package-lock.json"
}

t_dev_command() {
    new_repo sail
    local out lock
    for lock in "package-lock.json:npm" "yarn.lock:yarn" "pnpm-lock.yaml:pnpm"; do
        git rm -q -f --ignore-unmatch package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null
        echo '{}' > package.json; echo '{}' > "${lock%%:*}"; git add -A; git commit -qm "lock ${lock%%:*}"
        out=$("$S/up.sh" "feat/${lock##*:}" --skip $SAIL_SKIPS 2>/dev/null)
        case "${lock##*:}" in
            npm)  assert "npm forwards flags with --" contains "$out" "sail npm run dev -- --port" ;;
            *)    assert "${lock##*:} forwards flags without --" contains "$out" "sail ${lock##*:} run dev --port"
                  assert "${lock##*:} has no stray --" refute contains "$out" "dev -- --port" ;;
        esac
    done
}

t_lib() {
    new_repo
    MAIN_PATH="$REPO"; source "$S/lib.sh"
    assert "slugify" eq "$(slugify 'Foo/Bar.baz')" "foo-bar-baz"
    echo 'A=1' > .e; env_set A 2 .e; env_set B 3 .e
    assert "env_set replaces" eq "$(env_get A .e)" 2
    assert "env_set appends" eq "$(env_get B .e)" 3
    assert "env_get missing is empty" eq "$(env_get Z .e)" ""
    local K1=v K2=""; assert "emit omits empty" eq "$(emit K1 K2)" "K1=v"
    assert "compose_port_vars" eq "$(compose_port_vars compose.yaml | tr '\n' ',')" "APP_PORT $BASE_PORT,VITE_PORT $((BASE_PORT + 1)),FORWARD_DB_PORT $((BASE_PORT + 2)),"
    source "$SKILL_DIR/scripts/steps/60-deps.sh"
    assert "npm without lockfile" eq "$(_deps_node_args npm)" install
    touch package-lock.json; assert "npm with lockfile" eq "$(_deps_node_args npm)" ci
    assert "yarn classic" eq "$(_deps_node_args yarn)" "install --frozen-lockfile"
    touch .yarnrc.yml; assert "yarn berry" eq "$(_deps_node_args yarn)" "install --immutable"
    assert "pnpm" eq "$(_deps_node_args pnpm)" "install --frozen-lockfile"
    rm package-lock.json .yarnrc.yml
    rm -f pnpm-lock.yaml
    assert "node_lockfiles lists nothing when empty" eq "$(node_lockfiles | tr '\n' ',')" ""
    echo '{}' > yarn.lock; echo '{}' > package-lock.json
    assert "node_lockfiles lists several" eq "$(node_lockfiles | tr '\n' ',')" "package-lock.json,yarn.lock,"
    echo '{"packageManager": "pnpm@9.1.0"}' > package.json
    assert "declared packageManager beats lockfiles" eq "$(find_node_package_manager)" pnpm
    rm package.json yarn.lock package-lock.json
    assert "pkg manager defaults to npm" eq "$(find_node_package_manager)" npm
    touch pnpm-lock.yaml; assert "pkg manager from lockfile" eq "$(find_node_package_manager)" pnpm
}

# --- runner -----------------------------------------------------------------
filter="${1:-}"
RESULTS="$ROOT/results"; : > "$RESULTS"
for fn in $(declare -F | awk '{print $3}' | grep '^t_'); do
    [[ -z "$filter" || "$fn" == *"$filter"* ]] || continue
    echo "# $fn"
    ( "$fn" ) 2>&1 | tee -a "$RESULTS"
done

pass=$(grep -c '^ok' "$RESULTS" || true)
fail=$(grep -c '^not ok' "$RESULTS" || true)
echo "---"
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
