# desc: fail fast before anything changes — valid branch/base, not checked out elsewhere
#
# Needs: MAIN_PATH BRANCH BASE WORKTREES_DIR WORKTREE_PATH   (check only; runs for up)

step_preflight_check() {
    [[ "$PHASE" == up ]] || return 0

    git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 \
        || die "'$BRANCH' is not a valid git branch name. Try something like feature/my-change."

    [[ ! -e "$WORKTREES_DIR" || -d "$WORKTREES_DIR" ]] \
        || die "The worktrees location '$WORKTREES_DIR' exists but isn't a folder. Pick another with --dir or git config worktrees.dir."
    [[ "$WORKTREES_DIR" != "$MAIN_PATH" ]] \
        || die "The worktrees location can't be the project root itself. Pick a subfolder or another folder with --dir."

    if [[ ! -d "$WORKTREE_PATH" ]]; then
        local other
        other=$(list_worktrees | awk -v b="$BRANCH" '$2 == b {print $1}')
        [[ -z "$other" ]] || die "Branch '$BRANCH' is already checked out at $other. Use that worktree, or pick a different branch name."

        if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
            git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null \
                || die "Base '$BASE' doesn't resolve to a commit. Pass an existing branch or ref with --base <ref>."
        fi
    fi
}
