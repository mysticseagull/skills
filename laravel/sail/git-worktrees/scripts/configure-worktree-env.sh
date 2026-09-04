#!/usr/bin/env bash
# configure-worktree-env.sh — give a worktree its own .env with its own set of
# host ports, so its Sail stack can run alongside the main project's (and any
# sibling worktree's) without "port is already allocated" errors.
#
# Usage: configure-worktree-env.sh
# Run from inside the worktree directory. Finds the main project automatically.
#
# Which variables get offset is read from the compose file's own `ports:`
# blocks — not guessed from a *_PORT naming pattern in .env. That distinction
# matters: Laravel's own internal container-to-container config vars (DB_PORT,
# REDIS_PORT, MAIL_PORT, ...) also end in "_PORT" but must NEVER be touched —
# they're the real port the db/redis/mail service listens on inside the
# Docker network, unrelated to whatever host port is forwarded to it. And the
# reverse also happens: a project's .env commonly doesn't define APP_PORT or
# VITE_PORT at all, relying on the compose file's own `${APP_PORT:-80}`
# default — a naming-pattern scan over .env would silently skip those and
# leave the worktree colliding with the main project on port 80. Reading the
# compose file's ports: blocks directly avoids both failure modes.
#
# What it does, in order:
#   1. Copies .env from the main project (skipped if one already exists here)
#   2. Collects the host-side port variables from the compose file's ports:
#      blocks, along with each one's compose-file default
#   3. For each, resolves its current effective value (.env if set there,
#      otherwise the compose-file default)
#   4. Probes actual host ports to find the lowest offset (multiple of 10) at
#      which none of those effective values collide with anything already
#      bound — covers the main project, sibling worktrees, and anything else
#      running locally
#   5. Applies that offset to every one of those variables, adding the line to
#      .env if it wasn't already there
#   6. Points APP_URL/SESSION_DOMAIN at this worktree's own port, adding
#      either line if it doesn't already exist. Updates SANCTUM_STATEFUL_
#      DOMAINS too, but only if the project already set it — Sanctum's own
#      default already covers this worktree's origin via APP_URL otherwise
#   7. Pins COMPOSE_PROJECT_NAME to this worktree's folder name
#   8. Detects which Node package manager this project actually uses, from
#      its lockfile
#
# Prints KEY=value lines to stdout:
#   OFFSET                 the port offset applied
#   APP_PORT                this worktree's host port for the app
#   VITE_PORT                this worktree's host port for Vite — empty if the
#                            compose file's ports: blocks never mentioned it
#   COMPOSE_PROJECT_NAME
#   PKG_MANAGER             yarn|pnpm|npm — detected from the lockfile
#
# Exits 1 (with OFFSET left unset) if no free offset was found in 50 attempts
# — a sign something unusual is going on that needs a human look, not a guess.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib.sh"

compose_file=$(find_compose_file) || {
    echo "No compose file found (compose.yaml, compose.yml, docker-compose.yaml, or docker-compose.yml) — run this from inside the worktree directory" >&2
    exit 1
}

if [[ ! -f .env ]]; then
    main_project_path=$(find_main_project_path)
    if [[ ! -f "$main_project_path/.env" ]]; then
        echo "No .env found in this worktree or in the main project ($main_project_path)." >&2
        exit 1
    fi
    cp "$main_project_path/.env" .env
elif grep -q '^COMPOSE_PROJECT_NAME=' .env; then
    # COMPOSE_PROJECT_NAME is the marker this script itself writes at the end — its
    # presence means a previous run already offset this .env. Re-running the offset
    # logic against already-offset values would compound it, so treat this as a
    # no-op and report what's already there instead.
    echo "This .env is already configured (COMPOSE_PROJECT_NAME is set) — leaving it as-is." >&2
    cat <<EOF
OFFSET=already-configured
APP_PORT=$(grep '^APP_PORT=' .env | tail -1 | cut -d= -f2- || true)
VITE_PORT=$(grep '^VITE_PORT=' .env | tail -1 | cut -d= -f2- || true)
COMPOSE_PROJECT_NAME=$(grep '^COMPOSE_PROJECT_NAME=' .env | tail -1 | cut -d= -f2- || true)
PKG_MANAGER=$(find_node_package_manager)
EOF
    exit 0
fi

# --- collect host-forwarded port variables from the compose file's own
#     ports: blocks, e.g. `- '${APP_PORT:-80}:80'` -> APP_PORT, default 80 ---
port_var_names=()
port_var_defaults=()

in_ports_block=no
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*ports:[[:space:]]*$ ]]; then
        in_ports_block=yes
        continue
    fi
    if [[ "$in_ports_block" == yes ]]; then
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            if [[ "$line" =~ \$\{([A-Z_]+)(:-([0-9]+))?\} ]]; then
                var="${BASH_REMATCH[1]}"
                default="${BASH_REMATCH[3]}"
                seen=no
                for existing in ${port_var_names[@]+"${port_var_names[@]}"}; do
                    [[ "$existing" == "$var" ]] && seen=yes && break
                done
                if [[ "$seen" == no ]]; then
                    port_var_names+=("$var")
                    port_var_defaults+=("$default")
                fi
            fi
        else
            in_ports_block=no
        fi
    fi
done < "$compose_file"

if [[ "${#port_var_names[@]}" -eq 0 ]]; then
    echo "No host-forwarded port variables found in $compose_file's ports: blocks — nothing to offset." >&2
    exit 1
fi

# --- resolve each one's current effective value: .env if set there, else the
#     compose file's own default ---
port_var_currents=()
for i in "${!port_var_names[@]}"; do
    var="${port_var_names[$i]}"
    current=$(grep "^${var}=" .env 2>/dev/null | tail -1 | cut -d= -f2- || true)
    [[ -z "$current" ]] && current="${port_var_defaults[$i]}"
    port_var_currents+=("$current")
done

port_in_use() {
    (echo > "/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

offset=0
found=no
for attempt in $(seq 1 50); do
    candidate_offset=$((attempt * 10))
    conflict=no
    for current in "${port_var_currents[@]}"; do
        [[ -z "$current" ]] && continue
        candidate_port=$((current + candidate_offset))
        if port_in_use "$candidate_port"; then
            conflict=yes
            break
        fi
    done
    if [[ "$conflict" == no ]]; then
        offset=$candidate_offset
        found=yes
        break
    fi
done

if [[ "$found" == no ]]; then
    echo "Couldn't find a free port offset in 50 attempts — something unusual is going on here." >&2
    exit 1
fi

for i in "${!port_var_names[@]}"; do
    var="${port_var_names[$i]}"
    current="${port_var_currents[$i]}"
    [[ -z "$current" ]] && continue
    new_value=$((current + offset))
    if grep -q "^${var}=" .env; then
        sed_inplace "s|^${var}=.*|${var}=${new_value}|" .env
    else
        echo "${var}=${new_value}" >> .env
    fi
done

app_port=$(grep '^APP_PORT=' .env | tail -1 | cut -d= -f2- || true)
if [[ -z "$app_port" ]]; then
    echo "Couldn't determine APP_PORT after offsetting — check that $compose_file exposes it under ports: as \${APP_PORT...}." >&2
    exit 1
fi

# VITE_PORT isn't required the way APP_PORT is — a project could expose Vite
# some other way — so this is left empty rather than erroring if the compose
# file's ports: blocks never mentioned it.
vite_port=$(grep '^VITE_PORT=' .env | tail -1 | cut -d= -f2- || true)

if grep -q '^APP_URL=' .env; then
    sed_inplace "s|^APP_URL=.*|APP_URL=http://localhost:$app_port|" .env
else
    echo "APP_URL=http://localhost:$app_port" >> .env
fi

if grep -q '^SESSION_DOMAIN=' .env; then
    sed_inplace "s|^SESSION_DOMAIN=.*|SESSION_DOMAIN=localhost|" .env
else
    echo "SESSION_DOMAIN=localhost" >> .env
fi

# Only touch this if the project already set it explicitly. Unlike APP_URL/
# SESSION_DOMAIN, Sanctum falls back to its own built-in default stateful-
# domains list when the var is absent — appending a single-entry value here
# would replace that broader default with just this one entry. APP_URL is
# already set correctly above regardless, so leaving this alone when it was
# never set avoids narrowing Sanctum's own default for no clear benefit.
if grep -q '^SANCTUM_STATEFUL_DOMAINS=' .env; then
    sed_inplace "s|^SANCTUM_STATEFUL_DOMAINS=\(.*\)|SANCTUM_STATEFUL_DOMAINS=\1,localhost:$app_port|" .env
fi

compose_project_name=$(printf '%s' "$(basename "$PWD")" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')
if grep -q '^COMPOSE_PROJECT_NAME=' .env; then
    sed_inplace "s|^COMPOSE_PROJECT_NAME=.*|COMPOSE_PROJECT_NAME=$compose_project_name|" .env
else
    echo "COMPOSE_PROJECT_NAME=$compose_project_name" >> .env
fi

cat <<EOF
OFFSET=$offset
APP_PORT=$app_port
VITE_PORT=$vite_port
COMPOSE_PROJECT_NAME=$compose_project_name
PKG_MANAGER=$(find_node_package_manager)
EOF
