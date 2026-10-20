# desc: install node dependencies (and, in plain mode, composer) — sail: inside the stack; plain: on the host
#
# Node installs are lockfile-frozen (npm ci / yarn --frozen-lockfile|--immutable /
# pnpm --frozen-lockfile): faster, reproducible, and they never rewrite the
# lockfile — a plain `npm install` can, which would leave the fresh worktree dirty.
# If the lockfile has drifted from package.json the frozen install fails, and we
# fall back to a regular install with a warning.
#
# Under Sail, Composer dependencies are installed earlier by the bootstrap step.
#
# Needs: MODE WORKTREE_PATH DO_INSTALL

DO_INSTALL=yes

# _deps_node_args PM — the install arguments for PM, frozen when a lockfile exists.
_deps_node_args() {
    case "$1" in
        npm)  [[ -f package-lock.json ]] && echo "ci" || echo "install" ;;
        yarn) [[ -f .yarnrc.yml ]] && echo "install --immutable" || echo "install --frozen-lockfile" ;;
        pnpm) echo "install --frozen-lockfile" ;;
    esac
}

# _deps_node PM — runs the node install via sail (sail mode) or on the host.
_deps_node() {
    local pm="$1" runner=() args
    [[ "$MODE" == sail ]] && runner=(sail)
    args=$(_deps_node_args "$pm")

    if [[ "$args" != install ]]; then
        # shellcheck disable=SC2086  # args is deliberately word-split
        if try_logged ${runner[@]+"${runner[@]}"} "$pm" $args; then return 0; fi
        warn "$pm lockfile is out of sync with package.json — ran a regular install instead (it may modify the lockfile)."
    fi
    run_logged ${runner[@]+"${runner[@]}"} "$pm" install
}

step_deps_up() {
    [[ "$DO_INSTALL" == yes ]] || { skip "--no-install"; return 0; }
    cd "$WORKTREE_PATH"
    local pm lockfiles
    pm=$(find_node_package_manager)
    lockfiles=$(node_lockfiles | paste -sd, - | sed 's/,/ and /g')
    if [[ "$lockfiles" == *" and "* && -z "$(declared_package_manager)" ]]; then
        warn "Found $lockfiles — using $pm. Add a \"packageManager\" entry to package.json to choose explicitly."
    fi

    if [[ "$MODE" == sail ]]; then
        [[ -f package.json ]] || return 0
        progress "Installing Node dependencies"
        _deps_node "$pm"
    else
        progress "Installing Composer and Node dependencies"
        [[ -f composer.json ]] && command -v composer >/dev/null && run_logged composer install --no-interaction
        [[ -f package.json ]] && command -v "$pm" >/dev/null && _deps_node "$pm"
    fi
    return 0
}
