# desc: push the branch to origin (up, default; --no-push to skip); delete it there (down, if merged)
#
# Push is the default so work isn't stranded in a local worktree, but quick
# spin-offs that merge straight back can opt out. A missing origin or a failed
# push warns and continues local-only rather than failing the whole setup.
#
# On down, the remote branch is deleted automatically only when it's already
# merged into the main checkout's current branch (a pushed-but-unmerged branch
# may back a PR). --remote deletes it regardless; --keep-remote never does.
#
# Needs: BRANCH WORKTREE_PATH DO_PUSH DELETE_REMOTE(auto|yes|no)
# Sets: PUSHED REMOTE_DELETED

DO_PUSH=yes DELETE_REMOTE=auto PUSHED=no REMOTE_DELETED=no

step_remote_up() {
    [[ "$DO_PUSH" == yes ]] || { skip "--no-push"; return 0; }
    git remote get-url origin >/dev/null 2>&1 || { skip "no origin remote"; return 0; }

    progress "Pushing '$BRANCH' to origin"
    if try_logged git -C "$WORKTREE_PATH" push -u origin "$BRANCH"; then
        PUSHED=yes
    else
        warn "Couldn't push '$BRANCH' to origin (offline or no access?) — keeping it local. Details: $LOG"
    fi
}

step_remote_down() {
    [[ "$DELETE_REMOTE" != no ]] || { skip "--keep-remote"; return 0; }
    git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" || { skip "$BRANCH isn't on origin"; return 0; }

    if [[ "$DELETE_REMOTE" == auto ]] && ! git merge-base --is-ancestor "origin/$BRANCH" HEAD; then
        progress "Keeping origin/$BRANCH — it isn't merged into $(current_branch) yet (use --remote to delete it anyway)"
        return 0
    fi

    progress "Deleting '$BRANCH' on origin"
    if try_logged git push origin --delete "$BRANCH"; then
        REMOTE_DELETED=yes
    else
        warn "Couldn't delete '$BRANCH' on origin. Details: $LOG"
    fi
}
