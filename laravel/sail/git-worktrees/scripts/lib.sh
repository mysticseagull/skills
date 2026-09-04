#!/usr/bin/env bash
# lib.sh — shared helpers for the git-worktrees scripts.
#
# Sourced by the other scripts in this directory; not meant to be run directly.

# Portable `sed -i` across GNU sed (Linux) and BSD sed (macOS).
sed_inplace() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Prints the absolute path of the repo's main working tree (the checkout that
# isn't itself a linked worktree) — the first entry `git worktree list` ever
# reports. Run from anywhere inside the repo (main checkout or a worktree).
find_main_project_path() {
    git worktree list --porcelain | awk '/^worktree /{print $2; exit}'
}

# Prints the compose file name present in cwd, checked in the same order
# `docker compose` itself uses (compose.yaml, compose.yml, docker-compose.yaml,
# docker-compose.yml) — prints nothing if none exist.
find_compose_file() {
    for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        [[ -f "$f" ]] && echo "$f" && return 0
    done
    return 1
}

# Prints which Node package manager cwd actually uses, from its lockfile —
# never assume npm. Checks yarn.lock, pnpm-lock.yaml, then package-lock.json;
# falls back to npm only when none of those exist.
find_node_package_manager() {
    if [[ -f yarn.lock ]]; then
        echo yarn
    elif [[ -f pnpm-lock.yaml ]]; then
        echo pnpm
    elif [[ -f package-lock.json ]]; then
        echo npm
    else
        echo npm
    fi
}
