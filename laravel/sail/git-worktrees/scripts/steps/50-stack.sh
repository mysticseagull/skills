# desc: sail only — check Docker is reachable, start the worktree's own stack (up); remove it and its volumes (down)
#
# Needs: MODE WORKTREE_PATH   down also uses: KEEP_VOLUMES   Sets: STACK_REMOVED

KEEP_VOLUMES=no STACK_REMOVED=no

step_stack_check() {
    [[ "$PHASE" == up && "$MODE" == sail ]] || return 0
    command -v docker >/dev/null || die "Docker isn't installed or isn't on your PATH. Install it, or create just the worktree and .env with --skip bootstrap,stack,deps."
    docker info >/dev/null 2>&1 || die "Docker isn't running. Start Docker and try again, or create just the worktree and .env with --skip bootstrap,stack,deps."
}

step_stack_up() {
    [[ "$MODE" == sail ]] || { skip "not a sail project"; return 0; }
    cd "$WORKTREE_PATH"
    progress "Starting the Sail containers"
    run_logged sail up -d
}

step_stack_down() {
    command -v docker >/dev/null || { skip "docker not installed"; return 0; }
    cd "$WORKTREE_PATH"
    find_compose_file >/dev/null || { skip "no compose file"; return 0; }

    local flags=(--remove-orphans)
    [[ "$KEEP_VOLUMES" == no ]] && flags+=(--volumes)
    progress "Stopping and removing the Docker stack"
    if try_logged docker compose down "${flags[@]}"; then
        STACK_REMOVED=yes
    else
        warn "Couldn't cleanly remove the Docker stack — continuing anyway. Details: $LOG"
    fi
}
