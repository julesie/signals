# Deployment

## Render setup

- **Workspace:** `signals`
- **Infrastructure-as-code:** `render.yaml` in repo root
- **Web service:** Docker runtime, starter plan
- **Database:** PostgreSQL, basic-256mb plan (`signals-db`)

## Domain and DNS

- **Domain:** signalshealth.app
- **Registrar:** DNSimple
- **DNS:** Cloudflare
- **SSL:** Render terminates SSL at the proxy. The app is configured with `assume_ssl = true` and `force_ssl = true`. The `/up` health check endpoint is excluded from SSL redirect.

## Environment variables

| Variable | Where set | Purpose |
|----------|-----------|---------|
| `DATABASE_URL` | Auto from `render.yaml` | Postgres connection string |
| `RAILS_MASTER_KEY` | Render dashboard (manual) | Decrypts `credentials.yml.enc` |
| `RAILS_ENV` | `render.yaml` | Set to `production` |
| `RAILS_LOG_TO_STDOUT` | `render.yaml` | Enable log streaming |
| `SOLID_QUEUE_IN_PUMA` | `render.yaml` | Run SolidQueue supervisor inside Puma |
| `WEBHOOK_AUTH_TOKEN` | Render dashboard (manual) | Bearer token for Health Auto Export webhook |
| `OPENAI_API_KEY` | Render dashboard (Phase 3) | GPT-5 Nano API access |

## Build and deploy

The app deploys as a Docker container using the multi-stage `Dockerfile` in the repo root.

**Build** (Dockerfile — no database access):
1. Install gems (`bundle install` — cached unless `Gemfile.lock` changes)
2. Precompile bootsnap cache (gems and app code)
3. Precompile assets (Tailwind CSS, JS)
4. Produce a final slim image with non-root user and jemalloc

**Pre-deploy** (has database access, runs before new container starts):
1. `rails db:prepare` (creates database if missing, runs pending migrations)

**Start command** (from Dockerfile CMD):
`./bin/thrust ./bin/rails server` — Thruster (HTTP caching/compression proxy) in front of Puma.

## Database configuration

Production uses `DATABASE_URL` exclusively (set in `config/database.yml`). Do not add explicit `database`, `username`, or `password` fields to the production config — they override `DATABASE_URL` and break the Render connection.

Solid Cache and Solid Queue share the primary database via `DATABASE_URL`. Their tables are defined in `db/queue_schema.rb` and `db/cache_schema.rb`. If setting up a fresh database, load these schemas manually:

```bash
DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bundle exec rails db:schema:load:queue db:schema:load:cache
```

## Deploy process

1. Push to `main` on GitHub
2. Render auto-deploys (auto-deploy is set to "On Commit")
3. Docker image is built (cached layers make this fast for gem/asset-only changes)
4. Pre-deploy command runs migrations
5. New container starts with Thruster + Puma

## Render CLI

The Render CLI (`render`) can be used for service management:

```bash
render services                           # List services
render services --output json             # JSON output
render ssh srv-<id>                       # SSH into service
render blueprints validate                # Validate render.yaml
```

## Seed user

`jules@julescoleman.com` / `changeme123!` — created by `db/seeds.rb` via `find_or_create_by!`.
