# Local Development Setup

## Prerequisites

Install these before cloning:

| Tool | Install | Verify |
|------|---------|--------|
| **Homebrew** | [brew.sh](https://brew.sh) | `brew --version` |
| **rbenv** | `brew install rbenv` | `rbenv --version` |
| **Ruby 3.4.7** | `rbenv install 3.4.7` | `ruby --version` (in project dir) |
| **PostgreSQL** | `brew install postgresql@18` | `pg_isready` (should say "accepting connections") |
| **Node.js** | `brew install node` | `node --version` |
| **Foreman** | `gem install foreman` | `foreman version` |

> **Note:** rbenv automatically selects the correct Ruby version from `.ruby-version` when you `cd` into the project directory. Run `rbenv init` and follow the instructions to add it to your shell if you haven't already.

## Setup

```bash
git clone git@github.com:<your-org>/signals.git
cd signals
bin/setup --skip-server
```

`bin/setup` is idempotent and handles:

1. `bundle install` — installs gem dependencies
2. `lefthook install` — installs git hooks (linting + tests)
3. `db:prepare` — creates databases, runs migrations, seeds data (default user + historical CSV import)
4. Clears old logs and temp files

Pass `--reset` to drop and recreate databases from scratch.
Omit `--skip-server` to start the dev server immediately after setup.

## Running the App

```bash
bin/dev
```

This starts two processes via Foreman (`Procfile.dev`):

- **web** — Rails server on `http://localhost:3000`
- **css** — Tailwind CSS watcher for live style rebuilds

### Seed User

Sign in at `http://localhost:3000` with:

- **Email:** `jules@julescoleman.com`
- **Password:** `changeme123!`

## Common Commands

| Command | Purpose |
|---------|---------|
| `bin/dev` | Start dev server (web + CSS watcher) |
| `bin/rails test` | Run full test suite |
| `bin/rails db:seed` | Re-import CSV data + ensure seed user exists |
| `bin/rails db:reset` | Drop, recreate, migrate, and seed databases |
| `bundle exec standardrb --fix` | Auto-fix Ruby style issues |
| `bundle exec brakeman` | Run security audit |
| `bundle exec bundler-audit` | Check gems for known vulnerabilities |
| `bin/rails credentials:edit` | Edit encrypted credentials (needs `EDITOR` env var) |

## Database

Development uses PostgreSQL with the default local socket connection (no password needed). The database names are:

- `signals_development` — primary app data
- `signals_test` — test database (reset automatically by test runner)

Production adds two additional logical databases for Solid Cache and Solid Queue, all sharing a single Postgres instance via `DATABASE_URL`.

## Git Hooks (Lefthook)

Installed automatically by `bin/setup`. Re-install manually with `bundle exec lefthook install`.

- **Pre-commit:** runs `standardrb --fix` and re-stages corrected files
- **Pre-push:** runs `brakeman` (security) and `bin/rails test` (tests)

## Troubleshooting

**`pg_isready` says "no response"**
PostgreSQL isn't running. Start it with `brew services start postgresql@18`.

**`bundle install` fails on `pg` gem**
You may need to point it at the Homebrew Postgres:
```bash
gem install pg -- --with-pg-config=$(brew --prefix postgresql@18)/bin/pg_config
bundle install
```

**`rbenv: version 'X.Y.Z' is not installed`**
Install the required Ruby: `rbenv install $(cat .ruby-version)`
