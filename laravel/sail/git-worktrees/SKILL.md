---
name: git-worktrees
description: Use when setting up a Laravel worktree for local development with Laravel Sail, or when user asks to work on a feature branch in isolation
license: MIT
tags:
  - laravel
  - php
  - sail
  - docker
  - worktree
  - git
  - development
---

# Laravel Sail Worktree Setup

## Overview

Sets up a git worktree for Laravel projects served by Laravel Sail, ensuring the worktree runs its own isolated Docker Compose stack (unique ports, its own containers/volumes) alongside the main project's stack.

The deterministic parts of this — detecting the base branch, creating the worktree, seeding/building the Docker context, configuring `.env` — are bundled as tested scripts under `scripts/` (see the Scripts table below). **Run them instead of reconstructing their logic inline.** They compute values so you don't have to infer them, and they surface ambiguity (via `NEEDS_CONFIRMATION`-style output) rather than resolving it themselves — resolving it, or asking the user, stays your job.

**Announce at start:** "I'm using the laravel-sail git-worktrees skill to set up an isolated Laravel workspace with Sail."

## IMPORTANT: User Interaction Guidelines

**This skill is designed to run unattended** — a subagent or automated task runner should be able to spin up a worktree end-to-end without stopping for input. Default to deciding, not asking:

- **Decide automatically** (apply the stated default and keep moving, just say what you chose) for: base branch, port offset, Docker build-context seeding, and composer install flags. Each of these has a script-computed or safe default below — use it.
- **Use context you already have instead of asking.** If the branch name, or whether the user wants the worktree removed when done, is already stated anywhere in the current task, use it directly — don't re-ask for something you were already told.
- **Only use `AskUserQuestion`** when: (a) no branch name exists anywhere in context and one must be chosen, (b) multiple existing worktrees match and it's unclear which one to act on, (c) an automatic step fails and there's no safe default to fall back to, or (d) the action is destructive/irreversible and wasn't already explicitly requested (e.g. abandoning a worktree, discarding uncommitted changes). Never stop and silently wait — if you must ask, use `AskUserQuestion` so the workflow can continue.

All question blocks in this skill (shown in YAML-like format) should be implemented using the AskUserQuestion tool with the specified options, but only reached when the guidance above says to ask.

**Scope:** this skill covers setting up and running a git worktree with its own Laravel Sail stack — nothing past that. How a branch eventually gets integrated (or whether it's ever deleted) is the developer's own workflow and tooling, and out of scope here.

## When to Use

- User wants to work on a feature branch in isolation
- User mentions "worktree" and the project uses Laravel Sail
- Starting work on a task that needs isolation from main branch

## Initial Flow

1. **First, check if any worktrees already exist** using `git worktree list`
2. **If worktrees exist and the task doesn't already say which one (or that this is a new one)**, use AskUserQuestion to ask if they want to:
   - Set up a new worktree
   - Finish work on an existing worktree (then ask which one and proceed to "Finishing Work" section)
3. **Determine the branch name:**
   - **If the user gave an exact name, use it verbatim.**
   - **Otherwise, infer a reasonable one from the task** — short, kebab-case, matching this repo's existing prefix convention if one is evident (e.g. "fix the null check in checkout" → `fix/checkout-null-check`; "add password reset" → `feature/password-reset`). Say what you chose rather than asking.
   - **Only use AskUserQuestion if the task genuinely doesn't give enough to construct a sensible name** (too vague, or several equally plausible options) — don't ask just to confirm an inference that's already reasonable.

## Prerequisites

- **Docker** (Docker Desktop or compatible engine) installed and running
- **Laravel Sail** already configured in the main project (`vendor/bin/sail` and a compose file — `compose.yaml` or `docker-compose.yml` — present)
- **Git** for version control
- **Vite** as the frontend build tool (this skill assumes Vite, not Webpack/Mix)
- **A Node package manager** — npm, yarn, or pnpm; detected from the lockfile (Step 3), never assumed
- **Laravel Sanctum** if using API authentication (optional - skill handles this if present)

## Scripts

| Path | Purpose |
|---|---|
| `scripts/detect-base-branch.sh <branch-name>` | Detects whether origin uses git-flow (`develop`/`development`) or trunk-based (`main`/`master`), and whether `<branch-name>` is a hotfix-style name (`hotfix/`, `fix/`, `fix:`, etc.) that should skip the integration branch — then computes `$BASE_BRANCH`. Flags real ambiguity via `NEEDS_CONFIRMATION` rather than guessing. Run from the main project root. |
| `scripts/create-worktree.sh <branch-name> <base-branch>` | Fetches the base branch, creates (or reuses) the worktree explicitly off it, pushes the new branch immediately. Prints `$SITE_NAME`/`$WORKTREE_PATH`. Run from the main project root. |
| `scripts/bootstrap-sail.sh [--force-build]` | Seeds `vendor/laravel/sail` from the main project if needed, then builds the image only if it isn't already cached. Run from inside the worktree. |
| `scripts/configure-worktree-env.sh` | Copies `.env` from the main project, finds a free port offset by probing the host, applies it, updates `APP_URL`/`SESSION_DOMAIN`/`SANCTUM_STATEFUL_DOMAINS`/`COMPOSE_PROJECT_NAME`, and detects the Node package manager from its lockfile. Idempotent — a second run is a no-op. Run from inside the worktree. |
| `scripts/cleanup-worktree.sh <worktree-path>` | Stops the worktree's Sail stack and removes the worktree directory (doesn't touch the branch). Run from the main project root. |
| `scripts/lib.sh` | Shared helpers (`sed_inplace`, `find_main_project_path`, `find_compose_file`, `find_node_package_manager`) sourced by the scripts above — not run directly. |

Every script prints `KEY=value` lines to stdout for the values it computed; read them off and carry them forward into the next command yourself rather than re-deriving them.

**These scripts run with the target Laravel project (or its worktree) as the working directory — not this skill's own directory.** Invoke them by this skill's own path (e.g. `<this skill's base directory>/scripts/detect-base-branch.sh ...`) while `cd`'d into whichever directory the step calls for (the main project root, or the worktree). The rest of this document just writes `scripts/<name>.sh` for brevity — substitute the full path.

## Setup Steps

### 0. Detect the Base Branch

`$BRANCH_NAME` is already settled by Initial Flow step 3 before this point. **Detect whether this repo uses git-flow or trunk-based branching, and whether this branch's own name follows a hotfix-style convention — don't assume either.** Run from the main project's root:

```bash
scripts/detect-base-branch.sh "$BRANCH_NAME"
```

This checks origin for an integration branch (`develop` or `development`) and a trunk branch (`main` or `master`). Under git-flow, `$BASE_BRANCH` is normally the integration branch — except when `$BRANCH_NAME` itself matches a hotfix-style naming convention (`hotfix/`, `hotfix-`, `fix/`, `fix:`, `bugfix/`, `patch/`), which always bases off the trunk directly, bypassing the integration branch, since that's the standard convention for patching what's already released. It prints `STRATEGY`, `DEFAULT_BRANCH`, `INTEGRATION_BRANCH`, `IS_HOTFIX`, `BASE_BRANCH`, `CONVENTIONAL_COMMITS`, `NEEDS_CONFIRMATION`, and `NEEDS_CONFIRMATION_REASON`. If this repo names its hotfix branches something the script's list doesn't catch, that's a static list worth widening in the script itself.

**If `NEEDS_CONFIRMATION=yes`, use AskUserQuestion** rather than proceeding on the guess — `NEEDS_CONFIRMATION_REASON` explains why (neither `main` nor `master` found, or both `develop` and `development` exist and it's unclear which is real):

```
AskUserQuestion:
  question: "This repo's branching setup isn't clear ($NEEDS_CONFIRMATION_REASON). Which branch should '$BRANCH_NAME' be based on?"
  header: "Base Branch"
  options:
    - label: "$DEFAULT_BRANCH (Recommended)"
      description: "Origin's trunk branch"
    - label: "$INTEGRATION_BRANCH"
      description: "Origin's integration branch, if this repo follows git-flow"
    - label: "Custom branch"
      description: "I'll specify the exact base branch"
```

**If `CONVENTIONAL_COMMITS=yes`**, remember this repo likely cuts semantic version bumps from commit message prefixes (semantic-release, release-please, etc.) — prefix commit messages accordingly (`feat:`/`fix:`/`chore:`) for every commit made in this worktree, not just a final one, since an unprefixed commit may simply not trigger a release.

### 1. Create Worktree (if needed)

**Branch explicitly from `$BASE_BRANCH`, not from whatever happens to be checked out.** Branching from the current `HEAD` is the easy mistake here — it silently forks from the wrong point the moment someone's main checkout isn't sitting on the integration branch. Run from the main project's root:

```bash
scripts/create-worktree.sh "$BRANCH_NAME" "$BASE_BRANCH"
```

This fetches `$BASE_BRANCH`, creates the worktree explicitly off it (or reuses an existing one for this branch, including reattaching an orphaned local branch that has no worktree right now), and **pushes it immediately** — so the branch exists remotely and work isn't stranded only in a local worktree if the session ends or an agent crashes mid-task. Don't wait until "Finishing Work" for the first push. It prints `SITE_NAME` and `WORKTREE_PATH` — carry both forward into the remaining steps.

**Every commit and push made inside this worktree targets `$BRANCH_NAME`, and only `$BRANCH_NAME` — never `$BASE_BRANCH` or any other branch.** That's the entire point of the isolation: work on `feat-123` commits and pushes to `feat-123`, full stop. Always push with the branch named explicitly (`git push origin "$BRANCH_NAME"`) rather than a bare `git push` relying on default push behavior, and if there's ever doubt, confirm first:

```bash
[ "$(git branch --show-current)" = "$BRANCH_NAME" ] || echo "WARNING: not on $BRANCH_NAME — stop and check before pushing"
```

Push again as work progresses (`git add -A && git commit -m "..." && git push`) rather than hoarding commits locally until the end — this matters most when a subagent is doing the work unattended, since a push is the only thing that survives the session.

### 2. Bootstrap the Docker Build Context (vendor/ does not exist yet)

**CRITICAL: Worktrees do NOT share `vendor/` or `node_modules/` with the main project.** The compose file (`compose.yaml` or `docker-compose.yml`) itself is a tracked file, so it's already present in the fresh worktree checkout — but Sail's default setup points `build.context` at `./vendor/laravel/sail/runtimes/<version>/`, which lives *inside* the gitignored `vendor/` directory. That's a chicken-and-egg problem: the image can't build without that Dockerfile, and nothing can run in a container to install `vendor/` until the image builds.

**Don't try to solve this by guessing an external bootstrap image and PHP-version tag** (e.g. a `laravelsail/phpNN-composer` image on Docker Hub) — plenty of projects don't match that naming scheme at all: custom base images, private registries, non-standard runtime layouts, air-gapped/offline environments, or a PHP version newer than whatever's currently published. None of that guessing is necessary, because there's a copy of exactly the right Dockerfile sitting right next to this worktree, already proven to work: the main project's own `vendor/laravel/sail`.

```bash
cd "$WORKTREE_PATH"
scripts/bootstrap-sail.sh
```

It finds the main project automatically (via `git worktree list`), seeds `vendor/laravel/sail` and `vendor/bin/sail` from it if they're not already here, then builds — but **only if the resolved image tag isn't already cached locally**. Sail tags images by PHP runtime (e.g. `sail-8.4/app`), not by project, so the main project (or a sibling worktree) has usually already built it; skipping saves paying for that build again. It prints `MAIN_PROJECT_PATH`, `SEEDED`, and `BUILT`.

This seeds nothing more than what the main project already has working — no version detection, no registry lookups, no tag-existence checks. If this branch's `composer.lock` pins a different `laravel/sail` version, the real `composer install` in Step 4 corrects it automatically, since `vendor/` is bind-mounted and composer rewrites it in place.

**If the script exits with "nothing to seed from"** (the main project has no `vendor/` either — nothing bootstrapped anywhere on this machine yet), that's a genuine blocker, not something to guess past. Use AskUserQuestion (or ask directly) how they'd like to bootstrap Composer for the very first time.

**The only case that needs a rebuild regardless of what's cached is when this worktree's branch modifies the Dockerfile itself** (see the `sail:publish` note below — that's the file a rebuild would actually pick up). Everything else about a worktree (application code, config, ports) is irrelevant to the image and doesn't warrant one — pass `--force-build` only in that case:

```bash
scripts/bootstrap-sail.sh --force-build
```

All further commands run through `./vendor/bin/sail`.

**If this worktree's task is to change the Docker image itself** (add a PHP extension, swap the base image, change Node version, etc.), edit the compose file freely — it's tracked, so that part of the change flows through the branch like any other file. **Don't edit the seeded `vendor/laravel/sail` Dockerfile directly, though** — it's untracked, worktree-local, and a later `composer install` can silently overwrite it back to the locked version, so the edit would never make it into a commit and could vanish without warning. Publish it into tracked territory first, then edit the published copy:

```bash
# Once the stack is up (after Step 4) — copies the runtime Dockerfile and configs into
# ./docker at the project root and repoints the compose file's build context there
./vendor/bin/sail artisan sail:publish
```

After publishing, `./docker/` is a normal tracked directory — edit it, `git add` it, commit it. It also means any future worktree branched from this one no longer needs the seeding workaround at all, since the build context is now git-tracked rather than living inside `vendor/`.

### 3. Copy and Configure .env

Run from inside the worktree:

```bash
scripts/configure-worktree-env.sh
```

This copies `.env` from the main project (if one doesn't already exist here), probes actual host ports to find the lowest free offset, applies it to every `*_PORT` variable (`APP_PORT`, `VITE_PORT`, `FORWARD_DB_PORT`, `FORWARD_REDIS_PORT`, `FORWARD_MAILPIT_PORT`, `FORWARD_MAILPIT_DASHBOARD_PORT`, and anything else the project's `.env` defines), points `APP_URL`/`SESSION_DOMAIN`/`SANCTUM_STATEFUL_DOMAINS` at this worktree's own port, and pins `COMPOSE_PROJECT_NAME` to this worktree's folder name. It also checks the lockfile and prints which Node package manager this project actually uses. It prints `OFFSET`, `APP_PORT`, `VITE_PORT`, `COMPOSE_PROJECT_NAME`, and `PKG_MANAGER` — carry `$APP_PORT`, `$VITE_PORT`, and `$PKG_MANAGER` forward, all three are used later in this skill. It's idempotent: running it again against an already-configured `.env` is a no-op rather than compounding the offset.

### 4. Install Dependencies

**Run with no extra flags first — don't ask up front.**

```bash
# Bring up the worktree's own Sail stack (separate containers/volumes/network from main project)
./vendor/bin/sail up -d

# Re-run composer install through Sail now that containers are up
./vendor/bin/sail composer install
```

**Restart the stack now, before doing anything else.** `sail up -d` starts the app container before `vendor/autoload.php` exists (bootstrap-sail.sh only seeded the `laravel/sail` package, not a full install), so PHP crash-loops on boot and supervisord gives up permanently after its retry limit — composer install finishing afterward does *not* revive it. A restart clears that:

```bash
./vendor/bin/sail restart
```

**Install Node dependencies with whichever package manager this project actually uses — never assume npm.** `$PKG_MANAGER` is already known from Step 3's output (detected from the lockfile — `yarn.lock`, `pnpm-lock.yaml`, or `package-lock.json`), so just use it:

```bash
./vendor/bin/sail "$PKG_MANAGER" install

# Clear Laravel caches
./vendor/bin/sail artisan config:clear
./vendor/bin/sail artisan cache:clear

# Run migrations against this worktree's own database container
./vendor/bin/sail artisan migrate
```

**If `composer install` fails, automatically retry once** with the common fix before involving the user:

```bash
./vendor/bin/sail composer install --ignore-platform-reqs
```

**Only use AskUserQuestion if the retry also fails** — that's a real blocker needing human judgment, not something to guess past:

```
AskUserQuestion:
  question: "Composer install failed even with --ignore-platform-reqs. How should I proceed?"
  header: "Composer"
  options:
    - label: "Show the error for manual debugging (Recommended)"
      description: "Surface the exact error output so we can diagnose it together"
    - label: "Skip and continue"
      description: "Not recommended — later steps will likely fail without dependencies installed"
    - label: "Retry with custom flags"
      description: "I'll provide specific composer flags to try"
```

### 5. Start Dev Server on This Worktree's Own Port

**Don't edit `vite.config.js`/`vite.config.ts` for this.** Pass the port on the command line instead — a config edit is easy to forget mid-session and get swept into a commit on `$BRANCH_NAME` by an `add -A`. Vite's CLI flags override anything in the config file, including a hardcoded port, so this works no matter what the file currently does:

```bash
# $VITE_PORT and $PKG_MANAGER already known from Step 3's output

# Confirm containers are healthy
./vendor/bin/sail ps

# -- passes the flags through the package.json script to the underlying
# `vite` binary
./vendor/bin/sail "$PKG_MANAGER" run dev -- --port "$VITE_PORT" --strictPort
```

**If `$VITE_PORT` came back empty from Step 3**, this project's compose file doesn't publish a host port for Vite at all — check the compose file directly (`grep -n VITE_PORT` in it) before proceeding; that's a project-specific setup question outside what this skill can resolve automatically.

`--port`/`--strictPort` override `server.port`/`server.strictPort` from the config file, whether the config is silent on those or hardcodes something else.

**Don't add `--host 0.0.0.0`, even though the container needs to be reachable from the host.** `laravel-vite-plugin` already handles that itself: every Sail container sets `LARAVEL_SAIL=1`, and the plugin uses that to substitute `localhost` into the asset/HMR URLs it embeds in the page — but only when nothing has explicitly set `server.host`. Passing `--host 0.0.0.0` sets it, which suppresses that substitution and makes the plugin embed the literal bind address instead. The browser then gets `<script src="http://0.0.0.0:5183/...">` — `0.0.0.0` isn't a routable address from the browser's side, just a bind wildcard, so every asset fails with `net::ERR_ADDRESS_INVALID` and the page loads blank. Leaving `--host` off lets the plugin do its own substitution, resolves to `http://localhost:$VITE_PORT/...`, and the dev server is still reachable from the host exactly as before.

**Guardrail — check this if HMR doesn't connect:** Vite's HMR client normally infers its own port from wherever `--port` above put the server, no config involvement needed. The one case that breaks is a config file with an explicit `hmr: { port: <fixed number> }` — that overrides the CLI flag for the HMR channel specifically. Check for it:

```bash
grep -n 'hmr' vite.config.*
```

- Not present, or `hmr: true`/absent: nothing to do — the CLI flags above are enough, don't touch the file.
- A hardcoded `hmr.port`: this is the one case that does need a worktree-local edit. Keep it out of the branch:
  ```bash
  git update-index --skip-worktree vite.config.js   # or .ts
  ```
  (git stops tracking local changes to the file; undo later with `--no-skip-worktree` if it needs a real edit for this branch's actual work). Or, simpler, just remember to `git checkout -- vite.config.js` before "Finishing Work" and confirm with `git status` that it isn't in the diff.

**Why this matters:** `laravel-vite-plugin` reads `APP_URL`/`VITE_PORT` to wire up hot module replacement. If the wrong Vite instance or port is used, assets will fail to load or point to the wrong container.

**IMPORTANT:** Because this worktree's Sail stack uses its own offset ports and its own Docker Compose project, it can run **at the same time** as the main project's stack — no need to kill anything there. Just make sure nothing else on the host is already bound to this worktree's chosen ports.

**If the main project's own Vite dev server is also running**, expect it to notice file activity inside this worktree (`composer install`, `yarn install`, migrations touching generated files, etc.) and log spurious `changed tsconfig file detected` / `page reload` lines, or even full-reload the main project's browser tab. That's the main project's file watcher seeing `.worktrees/` as a subdirectory of its own project root — harmless, but see Common Issues below for the one-time fix if it's disruptive.

## Finishing Work

This skill's job is running the worktree, not integrating the branch anywhere — that's the developer's own workflow. When the user is done with a worktree:

1. **Commit and push whatever's left**, same as any other point during development:
   ```bash
   cd "$WORKTREE_PATH"
   git add -A
   git commit -m "..."   # only if there were changes
   git push
   ```
2. **Remove the worktree.** Run from the main project's root:
   ```bash
   scripts/cleanup-worktree.sh "$WORKTREE_PATH"
   ```
   This stops the Sail stack and removes the worktree directory. It doesn't touch the branch.

## Quick Reference

**Variables (mostly printed by the scripts — see the Scripts table):**
- `$BRANCH_NAME` - The git branch name (e.g., `feature/login`)
- `$SITE_NAME` - Worktree folder name, `<project-name>--<branch-name>`, printed by `create-worktree.sh` (e.g., `my-laravel-app--feature-login`)
- `$WORKTREE_PATH` - Relative path to the worktree, printed by `create-worktree.sh` (e.g., `.worktrees/my-laravel-app--feature-login`)
- `$OFFSET` - Port offset applied to every `*_PORT` value in `.env`, printed by `configure-worktree-env.sh`
- `$APP_PORT` - This worktree's host port for the app, printed by `configure-worktree-env.sh`
- `$VITE_PORT` - This worktree's host port for Vite, printed by `configure-worktree-env.sh` — empty if the compose file doesn't publish one
- `$STRATEGY` - `git-flow` or `trunk`, printed by `detect-base-branch.sh`
- `$DEFAULT_BRANCH` - Origin's trunk branch (`main` or `master`), printed by `detect-base-branch.sh`
- `$INTEGRATION_BRANCH` - Origin's integration branch (`develop` or `development`), printed by `detect-base-branch.sh` — empty if this repo doesn't have one
- `$IS_HOTFIX` - `yes`/`no`, printed by `detect-base-branch.sh`; whether `$BRANCH_NAME` matched a hotfix-style naming convention
- `$BASE_BRANCH` - The branch this worktree is forked from, printed by `detect-base-branch.sh`
- `$CONVENTIONAL_COMMITS` - `yes`/`no`, printed by `detect-base-branch.sh`; whether commit messages should be prefixed `feat:`/`fix:`/etc.
- `$PKG_MANAGER` - `yarn`/`pnpm`/`npm`, detected from the lockfile, printed by `configure-worktree-env.sh`

| Step | Command |
|------|---------|
| Detect base branch | `scripts/detect-base-branch.sh "$BRANCH_NAME"` (main project root) |
| Create worktree + push | `scripts/create-worktree.sh "$BRANCH_NAME" "$BASE_BRANCH"` (main project root) |
| Bootstrap + build Docker context | `scripts/bootstrap-sail.sh` (inside the worktree) |
| Configure .env | `scripts/configure-worktree-env.sh` (inside the worktree) |
| Bring stack up | `./vendor/bin/sail up -d` |
| Install PHP deps | `./vendor/bin/sail composer install` |
| Restart (PHP crash-looped before vendor/ existed) | `./vendor/bin/sail restart` |
| Install Node deps | `./vendor/bin/sail "$PKG_MANAGER" install` |
| Clear cache | `./vendor/bin/sail artisan config:clear && ./vendor/bin/sail artisan cache:clear` |
| Migrate | `./vendor/bin/sail artisan migrate` |
| Start dev | `./vendor/bin/sail "$PKG_MANAGER" run dev -- --port "$VITE_PORT" --strictPort` (no `--host`) |
| Tear down + remove worktree | `scripts/cleanup-worktree.sh "$WORKTREE_PATH"` (main project root; never touches the branch) |

## Common Issues

### Worktree forked from the wrong point
- **Cause:** `$BASE_BRANCH` was assumed instead of detected — e.g. hardcoded to `main` or to a specific integration-branch name that isn't what this repo actually uses, or `scripts/detect-base-branch.sh` was skipped and the worktree branched from whatever was checked out in the main directory at the time
- **Fix:**
  1. Re-run `scripts/detect-base-branch.sh "$BRANCH_NAME"`
  2. Tell the user the branch forked from the wrong point — moving it onto the correct base is a normal git operation outside this skill's scope

### "Bind for 0.0.0.0:PORT failed: port is already allocated"
- **Cause:** Another Sail project (main project or a different worktree) already has this port bound — usually because it wasn't running yet when `configure-worktree-env.sh` probed for a free offset
- **Fix:**
  1. Remove the `COMPOSE_PROJECT_NAME=` line (or the whole `.env`) and re-run `scripts/configure-worktree-env.sh` — it's a no-op while that line is present, so it has to go first to force a fresh probe
  2. Or find what's using the port: `docker ps --filter "publish=PORT"`

### 401 Unauthorized on API routes
- **Cause:** `SANCTUM_STATEFUL_DOMAINS` doesn't include the worktree's origin
- **Symptoms:** Login works but API calls return 401
- **Fix:**
  1. Add `localhost:$APP_PORT` to `SANCTUM_STATEFUL_DOMAINS` in `.env`
  2. Run `./vendor/bin/sail artisan config:clear`

### Cookie rejected for invalid domain
- **Cause:** `SESSION_DOMAIN` in `.env` doesn't match how the app is being accessed
- **Symptoms:** Console shows "Cookie has been rejected for invalid domain"
- **Fix:**
  1. Set `SESSION_DOMAIN=localhost` (or leave blank) in `.env`
  2. Run `./vendor/bin/sail artisan config:clear`
  3. Clear browser cookies for `localhost:$APP_PORT` (or use incognito)

### White page / CORS or connection refused on Vite assets
- **Cause:** Dev server started without the `--port "$VITE_PORT" --strictPort` flags from Setup Step 5, so it's not reachable from the host or not on the offset port
- **Fix:** Restart with the flags: `./vendor/bin/sail "$PKG_MANAGER" run dev -- --port "$VITE_PORT" --strictPort` (no `--host` — see the `ERR_ADDRESS_INVALID` entry below for why)

### Vite dev server prints `http://localhost:5173/` instead of the worktree's offset port
- **Cause:** Dev server started as plain `./vendor/bin/sail "$PKG_MANAGER" run dev` without the `-- --port "$VITE_PORT" --strictPort` flags — Vite falls back to its hardcoded default, and nothing on the host forwards to that port
- **Fix:** Restart per Setup Step 5, passing the flags. Don't reach for a `vite.config` edit here — the CLI flags are the fix

### Blank page, browser console shows `net::ERR_ADDRESS_INVALID` on every asset
- **Cause:** Dev server started with an explicit `--host 0.0.0.0` flag. That sets `server.host`, which suppresses `laravel-vite-plugin`'s own `LARAVEL_SAIL`-aware substitution and makes it embed the literal bind address in the page's `<script src="http://0.0.0.0:$VITE_PORT/...">` — `0.0.0.0` is a wildcard bind address, not something a browser can connect to
- **Fix:** Drop `--host` from the dev server command entirely — `./vendor/bin/sail "$PKG_MANAGER" run dev -- --port "$VITE_PORT" --strictPort`, no `--host`. The container is still reachable from the host without it; `curl http://localhost:$VITE_PORT/@vite/client` to confirm, and check the page source for `src="http://localhost:$VITE_PORT/...` (not `0.0.0.0`)

### HMR connects to the wrong port / websocket errors in the browser console
- **Cause:** `vite.config.js`/`vite.config.ts` hardcodes `hmr: { port: <fixed number> }`, which overrides the `--port` CLI flag for the HMR channel specifically (rare — most configs leave `hmr` alone and it just follows `--port`)
- **Fix:** The guardrail in Setup Step 5 — `grep -n 'hmr' vite.config.*` to confirm, then either `git update-index --skip-worktree` the file before editing it, or edit it and make sure `git checkout -- vite.config.js` runs before "Finishing Work" so the fix never reaches the branch

### Main project's Vite dev server logs `changed tsconfig file detected` / full-reloads while a worktree is being set up
- **Cause:** `.worktrees/` lives inside the main project's own directory tree, which is bind-mounted whole into the main project's own container. Its file watcher (chokidar, via Vite) doesn't know `.worktrees/` is a separate checkout and reacts to `composer install`/`yarn install`/migrations running there as if those were its own files changing. Harmless — the main project's actual source isn't touched — but noisy, and can force-reload the main project's open browser tab mid-work
- **Fix (optional, one-time, only if it's disruptive):** Not a worktree-scoped fix — this is a permanent addition to the **main project's own** `vite.config.js`/`.ts`, on whatever branch it's checked out to there, so treat it as a deliberate change the user reviews and commits themselves rather than something this skill applies automatically:
  ```javascript
  server: {
      watch: {
          ignored: ['**/.worktrees/**'],
      },
  },
  ```
  Confirm with the user before making this edit — it's outside this skill's normal scope of "run the worktree," since it touches the main checkout, not `$WORKTREE_PATH`.

### White page / 500 error right after first `sail up -d`
- **Cause:** The app container started before `vendor/autoload.php` existed (bootstrap-sail.sh only seeds the `laravel/sail` package), so PHP crash-looped and supervisord gave up permanently — composer install finishing afterward doesn't revive it on its own
- **Fix:** `./vendor/bin/sail restart`

### "vendor/bin/sail: No such file or directory"
- **Cause:** `vendor/` was never bootstrapped for this worktree — worktrees don't share `vendor/`
- **Fix:** Re-run `scripts/bootstrap-sail.sh` from inside the worktree

### `./vendor/bin/sail build` fails after seeding
- **Cause:** The seeded `vendor/laravel/sail` came from the main project's checkout and doesn't match what this branch's `composer.lock` expects (rare — only happens if this branch intentionally changed the `laravel/sail` version), or the main project's own `vendor/laravel/sail` was itself stale/broken
- **Fix:**
  1. Confirm the main project's own Sail stack builds and runs fine — if it doesn't, fix that first, since the seed can only be as good as its source
  2. Re-seed after running `composer update laravel/sail` (or equivalent) in the main project if this branch bumped the Sail version
  3. As a last resort, ask the user how they'd like to bootstrap — don't guess at an external image tag to paper over it

### Missing node_modules
- **Cause:** Worktrees don't share `node_modules/`
- **Fix:** Run `./vendor/bin/sail "$PKG_MANAGER" install` (`$PKG_MANAGER` comes from `configure-worktree-env.sh` in Setup Step 3 — re-run it if that's not already known; never assume npm)

### DB connection errors
- **Cause:** Missing `.env`, or `DB_HOST`/`DB_PORT` pointing at the wrong container
- **Fix:**
  1. If `.env` is missing entirely, re-run `scripts/configure-worktree-env.sh` from inside the worktree — it copies from the main project automatically
  2. Confirm `DB_HOST` matches the service name in this worktree's compose file (usually `mysql` or `pgsql`) — internal container-to-container hostnames don't need the offset, only the host-facing `FORWARD_*_PORT` values do

### Wrong containers responding / stale data
- **Cause:** Two worktrees ended up sharing a Docker Compose project name, so they share containers and volumes
- **Fix:** Set an explicit, unique `COMPOSE_PROJECT_NAME` per worktree (Setup Step 3) and recreate: `./vendor/bin/sail down --volumes && ./vendor/bin/sail up -d`

### Permission errors inside containers
- **Cause:** `WWWUSER`/`WWWGROUP` in `.env` don't match the host user
- **Fix:** Confirm `.env` has `WWWUSER=${WWWUSER:-1000}` / `WWWGROUP=${WWWGROUP:-1000}` (copied from the main project's `.env`, these don't need offsetting)

## Checklist

Before considering setup complete, verify:

- [ ] `$BASE_BRANCH` detected (not assumed) and worktree branched from `origin/$BASE_BRANCH`
- [ ] Worktree created at `$WORKTREE_PATH`
- [ ] `$BRANCH_NAME` pushed immediately with `-u` so it exists remotely from the start
- [ ] `vendor/` bootstrapped and `./vendor/bin/sail` exists
- [ ] `.env` copied and every `*_PORT` value offset by `$OFFSET`
- [ ] `APP_URL` updated to `http://localhost:$APP_PORT`
- [ ] `SESSION_DOMAIN` set to `localhost`
- [ ] `SANCTUM_STATEFUL_DOMAINS` includes `localhost:$APP_PORT` (if using Sanctum)
- [ ] `./vendor/bin/sail up -d` completed successfully
- [ ] `./vendor/bin/sail composer install` completed successfully
- [ ] `./vendor/bin/sail restart` run afterward (recovers PHP from the pre-vendor/ crash-loop)
- [ ] `$PKG_MANAGER` detected from the actual lockfile and `./vendor/bin/sail "$PKG_MANAGER" install` completed successfully
- [ ] `./vendor/bin/sail artisan migrate` completed successfully
- [ ] Dev server running with `-- --port "$VITE_PORT" --strictPort` (not a bare `run dev`, and no `--host`), and `vite.config.js`/`.ts` is untouched (`git status` clean) unless the hardcoded-`hmr.port` guardrail applied
- [ ] Site accessible at `http://localhost:$APP_PORT` (no white page)
- [ ] Main project's Sail stack still running fine (no port collisions)

## CRITICAL: Working Directory After Setup

**After worktree setup is complete, ALL subsequent work MUST use the worktree path.**

The worktree is a separate copy of the codebase. Using the main repo path will edit the wrong files.

- **Worktree path:** `$WORKTREE_PATH` (the absolute form of it, e.g. `/path/to/project/.worktrees/my-app--feature-login/`)
- **All file reads, edits, and writes** must use the worktree's absolute path (e.g., `/path/to/project/$WORKTREE_PATH/app/...`)
- **All commands** (artisan, tests, pint, etc.) must run through this worktree's own `./vendor/bin/sail` from the worktree directory — not the main project's
- **All git operations** must run from the worktree directory
- **All commits and pushes made here target `$BRANCH_NAME`, and only `$BRANCH_NAME`** — never push to `$BASE_BRANCH` or any other branch from inside a worktree; that defeats the isolation it exists for

**After setup, remind the user and any subsequent agents:** "All work for this task should use the worktree at `$WORKTREE_PATH`, running its own Sail stack. The site is accessible at `http://localhost:$APP_PORT`. Do not modify files in the main project directory, and always run commands through this worktree's `./vendor/bin/sail`, not the main project's."

## Integration

**Pairs with:**
- Git worktree workflows
- Any Laravel development workflow
