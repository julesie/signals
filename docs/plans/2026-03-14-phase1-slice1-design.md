# Phase 1, Slice 1: Rails App Shell + Auth + Deploy

**Date:** 2026-03-14
**Status:** Complete (deployed and verified on Render 2026-03-14)
**Goal:** Get a bare Rails 8 app running on Render behind Devise authentication.

## Decisions

- **Approach:** Manual `rails new` with selective flags — no templates, no Docker.
- **Ruby/Rails:** Ruby 3.3.x, Rails 8.0.
- **Deployment:** Render infrastructure-as-code via `render.yaml`.

## 1. Rails app scaffold

`rails new signals` with:
- `--database=postgresql`
- `--css=tailwind`
- `--skip-action-mailer --skip-action-mailbox --skip-action-text --skip-action-cable --skip-jbuilder`

The existing `PROJECT.md` moves to `docs/PROJECT.md` within the generated app.

## 2. Authentication (Devise)

- Add `devise` gem.
- Generate Devise install + `User` model.
- Disable `:registerable` — no sign-up page.
- `before_action :authenticate_user!` in `ApplicationController`.
- `db/seeds.rb` creates the single user (`jules@julescoleman.com`, temporary password `changeme123!`) using `find_or_create_by` for idempotency.

## 3. Root page

- `DashboardController#index` as root route, behind Devise auth.
- Minimal Tailwind-styled page with a "Signals" heading.

## 4. Render deployment (`render.yaml`)

- **Web service:** Ruby environment, `bundle install` build, `rails server` start. Env vars: `RAILS_MASTER_KEY`, `DATABASE_URL`.
- **Pre-deploy command:** `rails db:migrate && rails db:seed`.
- **Postgres:** Free tier database in the `signals` workspace.

## 5. Out of scope

- Webhook endpoint
- Health data tables (health_payloads, health_metrics, workouts)
- Dashboard content beyond placeholder
- Action Cable / Turbo Streams
- OpenAI integration
- Docker / docker-compose
