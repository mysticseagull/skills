# desc: give the worktree its own .env — sail: offset ports, APP_URL, session cookie, project name; plain: copy .env (down: release the port claim)
#
# Which variables get offset is read from the compose file's own `ports:` blocks —
# not guessed from a *_PORT naming pattern in .env. Laravel's internal
# container-to-container vars (DB_PORT, REDIS_PORT, MAIL_PORT, ...) also end in
# "_PORT" but must NEVER be touched, and a project's .env often omits APP_PORT or
# VITE_PORT entirely, relying on the compose file's `${APP_PORT:-80}` default — a
# naming-pattern scan would miss those and collide on port 80.
#
# Idempotent: COMPOSE_PROJECT_NAME is the marker a previous run leaves; while
# present, this is a no-op. To force a fresh port probe, delete that line from
# the worktree's .env and re-run (--only env) — offsets are always applied to
# the main project's base ports, so they never compound.
#
# Port offsets are claimed in a registry (see lib.sh) so a stopped sibling stack's
# ports aren't reused; down releases the claim.
#
# Needs: MODE MAIN_PATH BRANCH WORKTREE_PATH

step_env_up() {
    cd "$WORKTREE_PATH"
    if [[ -f .env && "$MODE" == sail && -n "$(env_get COMPOSE_PROJECT_NAME)" ]]; then
        trace ".env already configured"
        return 0
    fi

    if [[ ! -f .env ]]; then
        if [[ -f "$MAIN_PATH/.env" ]]; then
            cp "$MAIN_PATH/.env" .env
        elif [[ "$MODE" == sail ]]; then
            die "The main project has no .env to copy ($MAIN_PATH/.env). Create one there first."
        else
            skip "no .env to copy"
        fi
    fi
    [[ "$MODE" == sail ]] || return 0

    progress "Choosing free ports and writing this worktree's .env"
    local compose_file port_vars=() port_values=() var default value
    compose_file=$(find_compose_file)

    # Base value of each host-forwarded var: the main project's .env, else the
    # compose default — never this .env, which a previous run may have offset.
    while read -r var default; do
        value=$(env_get "$var" "$MAIN_PATH/.env")
        value="${value:-$default}"
        [[ -n "$value" ]] || continue
        port_vars+=("$var")
        port_values+=("$value")
    done < <(compose_port_vars "$compose_file")

    [[ "${#port_vars[@]}" -gt 0 ]] \
        || die "No host-forwarded port variables in $compose_file's ports: blocks — nothing to offset."

    local offset i
    offset=$(with_registry_lock allocate_offset "$BRANCH" "${port_values[@]}") \
        || die "Couldn't find a free set of ports (tried offsets up to 500). Stop some containers or free the ports and try again."
    trace "port offset $offset"

    for i in "${!port_vars[@]}"; do
        env_set "${port_vars[$i]}" $((port_values[i] + offset))
    done

    local app_port
    app_port=$(env_get APP_PORT)
    [[ -n "$app_port" ]] \
        || die "Couldn't determine APP_PORT — check that $compose_file exposes it under ports: as \${APP_PORT...}."
    env_set APP_URL "http://localhost:$app_port"
    env_set SESSION_DOMAIN localhost
    # Cookies are shared across ports on the same host, so give each worktree its
    # own session cookie name or logging in to one app logs you out of another.
    env_set SESSION_COOKIE "$(slugify "$(basename "$PWD")")_session"

    # Only extend if the project set it explicitly: Sanctum's built-in default
    # list applies when the var is absent, and a single entry would narrow it.
    if [[ -n "$(env_get SANCTUM_STATEFUL_DOMAINS)" ]]; then
        sed_inplace "s|^SANCTUM_STATEFUL_DOMAINS=\(.*\)|SANCTUM_STATEFUL_DOMAINS=\1,localhost:$app_port|" .env
    fi

    env_set COMPOSE_PROJECT_NAME "$(slugify "$(basename "$PWD")")"
}

step_env_down() {
    release_offset "$BRANCH"
}
