# Issue #13: Switch Render deployment from native runtime to Docker for faster builds

**Issue:** [#13](https://github.com/julesie/signals/issues/13)
**Branch:** `issue-13-switch-render-to-docker-deployment`
**Status:** Ready for Execution
**Created:** 2026-03-29

---

## Problem Summary

Render deploys are slow because the native Ruby runtime (`runtime: ruby`) reinstalls gems and recompiles assets from scratch on every push — there's no layer caching. The repo already has a well-structured multi-stage Dockerfile with proper caching (gems only reinstall when Gemfile.lock changes, assets only recompile when app code changes, bootsnap is precompiled). Switching to Docker-based deployment should dramatically speed up builds.

## Key Findings

### Current Setup (`render.yaml`)
- `runtime: ruby` with `buildCommand: ./bin/render-build.sh`
- Build script: `bundle install` + `rails assets:precompile` (runs fully every deploy)
- `preDeployCommand`: `bundle exec rails db:migrate && bundle exec rails db:seed`
- Start: `bundle exec puma -C config/puma.rb`
- Free tier for both web service and database
- Missing `SOLID_QUEUE_IN_PUMA` — background jobs not processing on Render

### Existing Dockerfile (ready to use)
- **Multi-stage build**: `base` → `build` → final (keeps image small)
- **Layer caching**: Gemfile/Gemfile.lock copied first, `bundle install` only reruns when they change
- **Bootsnap precompilation**: Both gems and app code (with `-j 1` QEMU workaround)
- **Asset precompilation**: `SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile`
- **Security**: Non-root user (uid 1000), jemalloc for memory optimization
- **Start command**: `./bin/thrust ./bin/rails server` (Thruster + Puma, exposes port 80)
- **Entrypoint** (`bin/docker-entrypoint`): Runs `db:prepare` before starting the server

### Render Docker Deployment Model
- Remove `runtime: ruby` and add `dockerfilePath: ./Dockerfile`
- Render sets `PORT` env var — Thruster and Puma both read it
- `preDeployCommand` runs after image build, before new container starts (ideal for migrations)
- `buildCommand` and `startCommand` are not used with Docker (Dockerfile handles both)

### Thruster (upgrade, no downside)
- Rust proxy (ships with Rails 8): HTTP caching, gzip/brotli compression, X-Sendfile
- Already in Gemfile and Dockerfile, just not used by native Render setup
- Reads `PORT` env var — Render's port injection works automatically

## Decisions Made

1. **Drop `db:seed` from preDeployCommand** — no longer needed on every deploy, can be run manually
2. **Keep `preDeployCommand` for `db:migrate`** — idiomatic Render location, visible in deploy logs. docker-entrypoint's `db:prepare` stays as a safety net for non-Render contexts (harmless no-op on Render since migrations already ran)
3. **Keep `bin/docker-entrypoint` unchanged** — preserves portability for Kamal/local Docker
4. **Use Thruster** — let Dockerfile CMD handle the start command (Thruster + Puma)
5. **Add `SOLID_QUEUE_IN_PUMA: true`** — enables background job processing in the web process (appropriate for single-server free-tier deploy)

## Step-by-Step Tasks

- [ ] 1. Update `render.yaml`: remove `runtime`, `buildCommand`, `startCommand`; add `dockerfilePath`; simplify `preDeployCommand` to `db:migrate` only; add `SOLID_QUEUE_IN_PUMA` env var
- [ ] 2. Delete `bin/render-build.sh` (no longer needed)
- [ ] 3. Verify Dockerfile builds locally: `docker build -t signals .`

## Open Questions / Unknowns

_(All resolved)_

---

*This plan is a living document — update it as understanding evolves.*
