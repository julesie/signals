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
| `WEBHOOK_AUTH_TOKEN` | Render dashboard (Phase 1) | Bearer token for Health Auto Export |
| `OPENAI_API_KEY` | Render dashboard (Phase 3) | GPT-5 Nano API access |

## Build and deploy

**Build** (`bin/render-build.sh` — no database access):
1. `bundle install`
2. `rails assets:precompile`

**Pre-deploy** (has database access, runs before new version starts):
1. `rails db:migrate`
2. `rails db:seed` (idempotent — safe to re-run)

Start command: `bundle exec puma -C config/puma.rb`

## SSL

Production is configured with `assume_ssl = true` and `force_ssl = true`. Render terminates SSL at the proxy. The `/up` health check endpoint is excluded from SSL redirect.

## Deploy process

1. Push to `main` on GitHub
2. Render auto-deploys from the blueprint
3. Verify at the Render URL — should see Devise sign-in page

## Seed user

`jules@julescoleman.com` / `changeme123!` — created by `db/seeds.rb` via `find_or_create_by!`.
