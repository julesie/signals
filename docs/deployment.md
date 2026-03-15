# Deployment

## Render setup

- **Workspace:** `signals`
- **Infrastructure-as-code:** `render.yaml` in repo root
- **Web service:** Ruby runtime, free tier
- **Database:** PostgreSQL, free tier (`signals-db`)

## Environment variables

| Variable | Where set | Purpose |
|----------|-----------|---------|
| `DATABASE_URL` | Auto from `render.yaml` | Postgres connection string |
| `RAILS_MASTER_KEY` | Render dashboard (manual) | Decrypts `credentials.yml.enc` |
| `RAILS_ENV` | `render.yaml` | Set to `production` |
| `RAILS_LOG_TO_STDOUT` | `render.yaml` | Enable log streaming |
| `WEBHOOK_AUTH_TOKEN` | Render dashboard (manual) | Bearer token for Health Auto Export webhook |
| `OPENAI_API_KEY` | Render dashboard (Phase 3) | GPT-5 Nano API access |

## Build and deploy

**Build** (`bin/render-build.sh` — no database access):
1. `bundle install`
2. `rails assets:precompile`

**Pre-deploy** (has database access, runs before new version starts):
1. `rails db:migrate`
2. `rails db:seed` (idempotent — safe to re-run)

Note: `preDeployCommand` in `render.yaml` is not picked up automatically by Render blueprints. Set it manually in the Render dashboard under Settings > Pre-Deploy Command.

Start command: `bundle exec puma -C config/puma.rb`

## SSL

Production is configured with `assume_ssl = true` and `force_ssl = true`. Render terminates SSL at the proxy. The `/up` health check endpoint is excluded from SSL redirect.

## Database configuration

Production uses `DATABASE_URL` exclusively (set in `config/database.yml`). Do not add explicit `database`, `username`, or `password` fields to the production config — they override `DATABASE_URL` and break the Render connection.

Solid Cache and Solid Queue share the primary database via `DATABASE_URL`.

## Deploy process

1. Push to `main` on GitHub
2. Render auto-deploys (auto-deploy is set to "On Commit")
3. Verify at the Render URL — should see Devise sign-in page

## Seed user

`jules@julescoleman.com` / `changeme123!` — created by `db/seeds.rb` via `find_or_create_by!`.
