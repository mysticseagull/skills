# Troubleshooting

Read only when `up.sh` fails or the worktree's site misbehaves. On failure `up.sh` prints the failing command, the log tail and the log path; re-run just the failing step with `--only <step> -v` to stream its full output (see `debugging.md`).

## Setup problems

### "Docker isn't running" / "Docker isn't installed"
The `stack` check runs before anything is created. Start Docker, or pass `--skip bootstrap,stack,deps` to create only the worktree and its `.env` (under Sail, `bootstrap` and `deps` also need Docker).

### "Sail isn't installed in the main project" / `vendor/bin/sail: No such file`
Worktrees don't share `vendor/`. The `bootstrap` step seeds `vendor/laravel/sail` from the main project, so run `composer install` there once. Don't guess an external bootstrap image; ask the user how to bootstrap Composer.

### `sail build` fails after seeding
The seeded `laravel/sail` doesn't match this branch's `composer.lock`, or the main project's copy is broken. Confirm the main stack builds first, then `scripts/up.sh <branch> --only bootstrap --rebuild`. To change the Docker image itself, run `sail artisan sail:publish` and edit the tracked `./docker` copy — not the seeded `vendor/` one.

### "port is already allocated"
Something unrelated to the worktrees bound the port (sibling worktrees are covered by the port registry; `scripts/status.sh` shows each offset). Remove the `COMPOSE_PROJECT_NAME=` line from the worktree's `.env` — its presence makes the `env` step a no-op — then `scripts/up.sh <branch> --only env,stack`. Find the holder with `docker ps --filter "publish=PORT"`. Offsets are always applied to the main project's ports, so repeating this never compounds.

### Offsets run out, or "timed out waiting for the port registry lock"
Claims live in `<git-dir>/worktree-ports` (`<offset> <branch>` per line). A worktree deleted by hand (not with `down.sh`) leaves its line behind — delete it. A killed run can leave `<git-dir>/worktree-ports.lock/` behind — `rmdir` it if no `up.sh` is running.

### Warnings
- **"Couldn't push … keeping it local"** — offline, no access, or no usable `origin`. The worktree is fine; push later with `git push -u origin <branch>`.
- **"Found package-lock.json and yarn.lock — using yarn"** — several lockfiles and no `packageManager` field. Add `"packageManager": "npm@…"` (or yarn/pnpm) to `package.json`, or delete the stray lockfile.
- **"<pm> lockfile is out of sync with package.json"** — the frozen install failed, so a regular install ran and may have modified the lockfile. Review `git status` before committing.

## Running the app

### White page / 500, or MySQL fails to start (stale mounts)
Composer ran *after* the stack started (e.g. `--no-install`, then installing by hand): replacing `vendor/laravel/sail` leaves the containers with stale bind mounts. Install, then recreate: `scripts/up.sh <branch> --only bootstrap,deps` and `./vendor/bin/sail up -d --force-recreate`.

### 500 until the dev server runs
Pages using `@vite` need `public/build` (gitignored) or a running dev server. `up.sh` doesn't start one — run `DEV_COMMAND`, or build assets.

### Vite
- Blank page, `ERR_ADDRESS_INVALID` on assets: the dev server was started with `--host 0.0.0.0`. Drop `--host`; `laravel-vite-plugin` substitutes `localhost` itself under Sail.
- Dev server on 5173, or assets 404: started without the worktree's `--port $VITE_PORT --strictPort`. Use `DEV_COMMAND` as printed (npm needs `--` before the flags; yarn and pnpm don't).
- HMR websocket errors: `grep -n hmr vite.config.*`. Only a hardcoded `hmr.port` breaks it — `git update-index --skip-worktree` that file before editing, or restore it before committing.
- The main project's Vite logs spurious `changed tsconfig` / reloads: its watcher sees the worktrees folder (`.gitworktrees/` by default). Optional fix in the *main* project's vite config (ask the user first): `server.watch.ignored: ['**/.gitworktrees/**']`.

### 401 on API routes / cookie rejected
`SANCTUM_STATEFUL_DOMAINS` must include `localhost:<APP_PORT>` (only edited if the project set it), and `SESSION_DOMAIN=localhost`. Then `./vendor/bin/sail artisan config:clear`.

### Logged out of one app after logging in to another
Cookies are shared across ports on `localhost`. `env` gives each worktree its own `SESSION_COOKIE` (`<project>--<branch>_session`); worktrees configured before that was added need it set by hand, then `config:clear`. Laravel's `XSRF-TOKEN` cookie name is fixed and still shared; it's reissued on every response, so a stray 419 clears on reload.

### DB connection errors
`.env` missing: `scripts/up.sh <branch> --only env`. `DB_HOST` must be the compose service name (`mysql`/`pgsql`); only the host-facing `FORWARD_*_PORT` values are offset, not `DB_PORT`.

### Wrong containers / stale data
Two worktrees share a compose project name. Set a unique `COMPOSE_PROJECT_NAME` in `.env`, then `sail down --volumes && sail up -d`.

### Permission errors in containers
`WWWUSER`/`WWWGROUP` in `.env` must match the host user (copied from main; not offset). Running `docker compose` by hand prints "WWWUSER variable is not set" — harmless; use `./vendor/bin/sail`, which sets them.

## `down.sh` refuses or can't find the worktree
- "uncommitted changes": commit or stash, or `--force` to discard.
- "neither merged … nor pushed": push the branch, merge it, `--keep-branch`, or `--force` to discard the commits.
- "No worktree found": `scripts/status.sh` lists what exists; pass the branch name or the worktree path.
