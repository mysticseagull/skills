# desc: run migrations and/or seeders (only with --migrate / --seed)
#
# Needs: MODE WORKTREE_PATH DO_MIGRATE DO_SEED   Sets: MIGRATED SEEDED

DO_MIGRATE=no DO_SEED=no MIGRATED=no SEEDED=no

step_database_up() {
    [[ "$DO_MIGRATE" == yes || "$DO_SEED" == yes ]] || { skip "no --migrate/--seed"; return 0; }
    cd "$WORKTREE_PATH"
    if [[ "$DO_MIGRATE" == yes ]]; then
        progress "Running migrations"
        run_logged artisan migrate --force
        MIGRATED=yes
    fi
    if [[ "$DO_SEED" == yes ]]; then
        progress "Seeding the database"
        run_logged artisan db:seed --force
        SEEDED=yes
    fi
}
