# desc: sail only — seed vendor/laravel/sail, build the image if not cached, install composer dependencies
#
# A fresh worktree has no vendor/ (gitignored), so there's no `sail` command, and
# nothing can run in a container to install vendor/ without one. Seed just
# vendor/laravel/sail from the main project's working vendor/ rather than guessing
# at an external bootstrap image. (sail:publish doesn't help: vendor/bin/sail
# itself still lives inside the package.)
#
# The build is skipped when the resolved image tag already exists locally — Sail
# tags images by PHP runtime, not by project, so the main project or a sibling
# worktree has usually built it. --rebuild forces it, e.g. after this branch
# changed the Dockerfile.
#
# Composer dependencies are installed here, in a one-off container, *before* the
# stack starts. Doing it after `sail up` replaces vendor/laravel/sail under the
# running containers, leaving stale bind mounts (MySQL's init script) that make
# `sail restart` fail, and the app container crash-loops until vendor/ exists.
# This way the stack starts once, with everything in place.
#
# Needs: MODE MAIN_PATH WORKTREE_PATH REBUILD DO_INSTALL

REBUILD=no

step_bootstrap_up() {
    [[ "$MODE" == sail ]] || { skip "not a sail project"; return 0; }
    cd "$WORKTREE_PATH"

    if [[ ! -d vendor/laravel/sail ]]; then
        [[ -d "$MAIN_PATH/vendor/laravel/sail" ]] \
            || die "Sail isn't installed in the main project ($MAIN_PATH). Run composer install there once, then try again."
        progress "Setting up Sail: copying vendor/laravel/sail from the main project"
        mkdir -p vendor/laravel vendor/bin
        cp -r "$MAIN_PATH/vendor/laravel/sail" vendor/laravel/sail
        cp vendor/laravel/sail/bin/sail vendor/bin/sail
        chmod +x vendor/bin/sail
    fi
    [[ -x vendor/bin/sail ]] || die "vendor/bin/sail still doesn't exist after seeding from $MAIN_PATH."

    local image_tag
    image_tag=$(docker compose config --images 2>/dev/null | head -1 || true)
    if [[ "$REBUILD" == yes || -z "$image_tag" ]] || ! docker image inspect "$image_tag" >/dev/null 2>&1; then
        progress "Building the Sail image (the first build can take a few minutes)"
        run_logged sail build
    else
        trace "image $image_tag already cached"
    fi

    [[ "$DO_INSTALL" == yes ]] || { skip "--no-install"; return 0; }
    progress "Installing Composer dependencies"
    try_logged _bootstrap_composer || run_logged _bootstrap_composer --ignore-platform-reqs
}

# _bootstrap_composer [EXTRA_ARGS] — composer install in a one-off app container
# (sail's own wrapper refuses to run anything while the stack is down).
_bootstrap_composer() {
    local app
    app=$(env_get APP_SERVICE)
    WWWUSER="${WWWUSER:-$(id -u)}" WWWGROUP="${WWWGROUP:-$(id -g)}" \
        docker compose run --rm --no-deps -T "${app:-laravel.test}" composer install --no-interaction "$@"
}
