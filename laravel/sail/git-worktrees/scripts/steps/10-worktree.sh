# desc: create the git worktree (up); remove it and its local branch (down)
#
# Needs: MAIN_PATH BRANCH BASE WORKTREES_DIR WORKTREE_PATH   (clears BASE if the branch already existed)   Sets: WORKTREE_REMOVED BRANCH_DELETED
# down also uses: FORCE_FLAG KEEP_BRANCH

FORCE_FLAG="" KEEP_BRANCH=no WORKTREE_REMOVED=no BRANCH_DELETED=no

step_worktree_up() {
    # A worktrees folder inside the project would show up as untracked; hide it
    # via the repo-local exclude file without touching anything tracked.
    if [[ "$WORKTREES_DIR" == "$MAIN_PATH"/* ]]; then
        local exclude entry
        exclude="$(git rev-parse --git-common-dir)/info/exclude"
        entry="/${WORKTREES_DIR#"$MAIN_PATH"/}/"
        grep -qxF "$entry" "$exclude" 2>/dev/null || echo "$entry" >> "$exclude"
    fi

    # BASE only means something when the branch is created here; otherwise clear
    # it so the summary and output don't claim a fork point that isn't true.
    if [[ -d "$WORKTREE_PATH" ]]; then
        progress "Worktree already exists — reusing it"
        BASE=""
    elif git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        progress "Branch '$BRANCH' already exists — checking it out in a new worktree"
        BASE=""
        run_logged git worktree add "$WORKTREE_PATH" "$BRANCH"
    else
        progress "Creating worktree for '$BRANCH' (from '$BASE')"
        run_logged git worktree add "$WORKTREE_PATH" -b "$BRANCH" "$BASE"
    fi
}

step_worktree_check() {
    [[ "$PHASE" == down ]] || return 0
    if [[ -z "$FORCE_FLAG" && -n "$(git -C "$WORKTREE_PATH" status --porcelain)" ]]; then
        die "This worktree has uncommitted changes. Commit or stash them first, or pass --force to discard them."
    fi

    if [[ "$KEEP_BRANCH" == no && -z "$FORCE_FLAG" ]]; then
        if ! git merge-base --is-ancestor "$BRANCH" HEAD 2>/dev/null \
            && ! { git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" \
                   && git merge-base --is-ancestor "$BRANCH" "origin/$BRANCH"; }; then
            die "Branch '$BRANCH' has commits that are neither merged into $(current_branch) nor pushed to origin. Push or merge it first, keep the branch with --keep-branch, or discard it with --force."
        fi
    fi
}

step_worktree_down() {
    progress "Removing the worktree"
    run_logged git worktree remove ${FORCE_FLAG:+"$FORCE_FLAG"} "$WORKTREE_PATH"
    WORKTREE_REMOVED=yes

    if [[ "$KEEP_BRANCH" == no && "$BRANCH" != "$(current_branch)" ]]; then
        progress "Deleting local branch '$BRANCH'"
        run_logged git branch -D "$BRANCH"
        BRANCH_DELETED=yes
    fi
}
