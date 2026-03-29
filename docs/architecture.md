# Architecture

## Tech stack

- **Ruby 3.3.10 / Rails 8.1** with Puma
- **PostgreSQL** — primary data store
- **Tailwind CSS** — all styling, component-driven
- **Devise** — single-user email/password auth (registration disabled)
- **Solid Queue / Solid Cache** — job processing and caching, backed by the primary Postgres database
- **Hotwire** (Turbo + Stimulus) — frontend interactivity (Phase 2+)
- **GPT-5 Nano** via `ruby_llm` gem — LLM coaching

## Data split: markdown vs Postgres

- **Markdown files** — anything the LLM reads/writes: training plans, nutrition goals, coaching notes, personal context.
- **Postgres** — anything that needs querying, trending, or deduplication: health metrics, workout records, body composition, strength logs.

The context assembly layer merges both into a single prompt. The guiding principle: if you'd want an LLM to edit it, it's markdown. If you'd want to run SQL against it, it's Postgres.

## Data pipeline

Health Auto Export (iOS) → HTTP POST with JSON → webhook endpoint (bearer token auth) → raw payload logging → parse and store.

**Sync strategy:** Health Auto Export configured with Day grouping — data arrives pre-aggregated as one value per metric per day. Two automations:
- "Previous 7 Days" every few hours — keeps the last week current
- "Yesterday" once daily — safety net for complete previous day

**Replace semantics:** Latest payload for a given day overwrites the previous values. No accumulation logic — each sync is self-contained and self-healing.

**Historical backfill:** 30 days of CSV data in `db/seed_data/`, imported via `db:seed` on deploy.

## Service objects

Business logic lives in `app/services/`, keeping models thin:
- `HealthDataProcessor` — orchestrates webhook payload processing in a transaction
- `MetricsParser` — parses health metrics from payload with upsert (create or replace) semantics
- `WorkoutParser` — parses workouts from payload, deduplicates on Health Auto Export UUID
- `CsvImporter` — one-time historical data import from Health Auto Export CSV files
- `HealthDataReprocessor` — rebuilds all health data from stored payloads (deduplicates overlapping data)
- `PlanSuggestionGenerator` — assembles plan + recent activity context, calls LLM, caches daily suggestion
- `PlanChatService` — single-shot conversational plan editing via LLM

## Database tables

**Current:**
- `users` — Devise authentication (single user)
- `health_payloads` — raw webhook JSON, processing status
- `health_metrics` — non-workout readings, JSONB metadata, deduplicated on `(metric_name, recorded_at)`
- `workouts` — workout sessions, JSONB for type-specific data, deduplicated on Health Auto Export UUID
- `plans` — single fitness plan per user (text content, cached daily suggestion), unique on `user_id`

**Phase 4:**
- `strength_sessions` — exercises, sets, reps, weight, RPE

## Key decisions

- **Single-user app.** No multi-tenancy, no registration page. User is seeded.
- **No Action Mailer/Mailbox/Text/Cable.** Skipped at generation. Cable will be added back for Turbo Streams in Phase 2.
- **Health Auto Export** as the HealthKit bridge. No direct HealthKit integration — Apple has no server-side API.
- **Webhook uses bearer token auth**, not Devise sessions, so the iOS app can POST directly.
- **Solid Queue and Solid Cache share the primary database** (free Render tier has one Postgres instance).
