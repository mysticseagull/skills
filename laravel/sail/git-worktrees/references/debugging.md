# Debugging and internals

## How it's built
`up.sh` and `down.sh` parse flags, resolve context, then run a pipeline of small steps in `scripts/steps/NN-name.sh`. `up` runs them in order, `down` in reverse. Every selected step's `_check` runs first (`PHASE` says which phase), so a refusal changes nothing.

| Step | up | down |
|---|---|---|
| `preflight` | valid branch/base, not checked out elsewhere, worktrees folder usable | — |
| `worktree` | create (or reuse/attach), hide the folder via `.git/info/exclude` | refuse if dirty/unmerged; remove worktree and local branch |
| `remote` | push to origin (default) | delete the remote branch if merged (or `--remote`) |
| `bootstrap` | Sail: seed `vendor/laravel/sail`, build image if not cached, `composer install` in a one-off container | — |
| `env` | Sail: free ports, `APP_URL`, `SESSION_COOKIE`, project name; plain: copy `.env` | release the port claim |
| `stack` | check Docker; `sail up -d` | `docker compose down` (+ volumes) |
| `deps` | frozen node install (plain mode also composer) | — |
| `database` | `--migrate` / `--seed` | — |

Composer runs in `bootstrap`, before the stack starts, on purpose: replacing `vendor/laravel/sail` under running containers leaves stale bind mounts (MySQL's init script) and a restart then fails.

`down`'s order matters: `remote` runs before `worktree` (it needs the branch and worktree present), so `--only worktree` on `down` skips remote cleanup — select dependent steps together.

To add behavior, add `steps/NN-name.sh` defining `step_name_up` (optionally `_down`, `_check`). Steps share state through globals, must be idempotent, and call `skip "reason"` when not applicable. Each step file owns its variables' defaults.

## Flags (both scripts)
`--list` show steps · `--only a,b` · `--skip a,b` · `--from a` · `--dry-run` · `-v`/`--verbose` (trace, stream command output, dump context). A failed command prints the step name and the exact retry command; steps are idempotent, so re-running one is safe.

## Output modes
- **Agent / pipe** (stderr not a terminal): stdout is `KEY=value` only (empty keys omitted); stderr is silent unless there's an `error:` or `warning:`.
- **Human** (stderr is a terminal): friendly progress, a labelled summary with next steps, `✖`/`⚠` messages, color unless `NO_COLOR` is set. `KEY=value` isn't printed when stdout is a terminal — pipe to `cat` to see it.
- `WT_PROGRESS=1` forces human mode, `WT_PROGRESS=0` forces agent mode; `WT_VERBOSE=1` = `-v`. Command output goes to a temp log (path printed on failure, deleted on success).

## Port registry
`<git-dir>/worktree-ports`, one `<offset> <branch>` line per worktree; offsets are multiples of 10 added to every host-forwarded port in the compose file, always on top of the **main project's** values. Allocation takes a `mkdir` lock (`worktree-ports.lock`) so parallel `up.sh` runs get distinct offsets, skips claimed offsets and currently-bound ports, and `down` releases the claim.

## Tests
`tests/run.sh [filter]` — dependency-free; each `t_*` runs in a throwaway repo. Sail mode is simulated (stub `vendor/laravel/sail`, `--skip bootstrap,stack,deps`) and package managers are stubbed, so **no Docker is needed and the real Docker paths aren't covered**: the image build, `sail up`, one-off composer install, node install in the container, migrate/seed, and `docker compose down`. Those were verified by hand on a real Sail app (MySQL, Redis, Mailpit, Vite) running next to the main stack; re-verify on a real project after changing `bootstrap`, `stack` or `deps`. Terminal-mode output is tested under a pseudo-terminal (needs `python3`).
