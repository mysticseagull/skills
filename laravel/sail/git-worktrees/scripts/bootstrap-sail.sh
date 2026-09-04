#!/usr/bin/env bash
# bootstrap-sail.sh — get a fresh worktree's Docker build context ready and,
# unless it's already cached, build the image.
#
# Usage: bootstrap-sail.sh [--force-build]
# Run from inside the worktree directory.
#
# The actual `sail` CLI script — vendor/bin/sail — lives inside the
# laravel/sail composer package at vendor/laravel/sail/bin/sail, which is
# gitignored. That's true whether or not the project has published its own
# copy of the Dockerfile via `sail artisan sail:publish` (publishing only
# relocates the Dockerfile to a tracked ./docker directory; it doesn't touch
# vendor/laravel/sail or make the CLI script itself available). Either way, a
# fresh worktree has no vendor/ at all, so there's no `sail` command yet — and
# nothing can run in a container to install vendor/ without one. Solve it by
# seeding just that one small package directory from the main project's
# already-working vendor/, rather than guessing at an external bootstrap image.
#
# Building is skipped when the resolved image tag already exists locally —
# Sail tags images by PHP runtime, not by project, so the main project (or a
# sibling worktree) has usually already built it. Pass --force-build to
# rebuild anyway, e.g. after this branch changed the Dockerfile itself.
#
# Prints KEY=value lines to stdout:
#   MAIN_PROJECT_PATH   path seeded from
#   SEEDED              yes|no|not-needed
#   BUILT                yes|no|skipped

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib.sh"

force_build=no
[[ "${1:-}" == "--force-build" ]] && force_build=yes

compose_file=$(find_compose_file) || {
    echo "No compose file found (compose.yaml, compose.yml, docker-compose.yaml, or docker-compose.yml) — run this from inside the worktree directory" >&2
    exit 1
}

main_project_path=$(find_main_project_path)
seeded=not-needed

if [[ ! -d vendor/laravel/sail ]]; then
    if [[ ! -d "$main_project_path/vendor/laravel/sail" ]]; then
        echo "Neither this worktree nor the main project ($main_project_path) has vendor/laravel/sail installed." >&2
        echo "There's nothing to seed from — bootstrap Composer in the main project first." >&2
        exit 1
    fi

    mkdir -p vendor/laravel
    cp -r "$main_project_path/vendor/laravel/sail" vendor/laravel/sail

    mkdir -p vendor/bin
    cp vendor/laravel/sail/bin/sail vendor/bin/sail
    chmod +x vendor/bin/sail
    seeded=yes
else
    seeded=no
fi

if [[ ! -x vendor/bin/sail ]]; then
    echo "vendor/bin/sail still doesn't exist after seeding from $main_project_path — something's off with that source." >&2
    exit 1
fi

built=skipped
if [[ "$force_build" == yes ]]; then
    ./vendor/bin/sail build
    built=yes
else
    image_tag=$(docker compose config --images 2>/dev/null | head -1 || true)
    if [[ -n "$image_tag" ]] && docker image inspect "$image_tag" >/dev/null 2>&1; then
        built=skipped
    else
        ./vendor/bin/sail build
        built=yes
    fi
fi

cat <<EOF
MAIN_PROJECT_PATH=$main_project_path
SEEDED=$seeded
BUILT=$built
EOF
