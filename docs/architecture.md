# Architecture

## Tech stack

- **Ruby 3.3.10 / Rails 8.1** with Puma
- **PostgreSQL** — primary data store
- **Tailwind CSS** — all styling, component-driven
- **Devise** — single-user email/password auth (registration disabled)
- **Solid Queue / Solid Cache** — job processing and caching, backed by the primary Postgres database
- **Hotwire** (Turbo + Stimulus) — frontend interactivity (Phase 2+)
- **GPT-5 Nano** via OpenAI API — LLM coaching (Phase 3+)

## Data split: markdown vs Postgres

- **Markdown files** — anything the LLM reads/writes: training plans, nutrition goals, coaching notes, personal context.
- **Postgres** — anything that needs querying, trending, or deduplication: health metrics, workout records, body composition, strength logs.

The context assembly layer merges both into a single prompt. The guiding principle: if you'd want an LLM to edit it, it's markdown. If you'd want to run SQL against it, it's Postgres.

## Data pipeline

Health Auto Export (iOS) → HTTP POST with JSON → webhook endpoint (bearer token auth) → raw payload logging → parse and store with deduplication.

## Service objects

Business logic lives in `app/services/`, keeping models thin:
- `HealthDataProcessor` — orchestrates webhook payload processing in a transaction
- `MetricsParser` — parses health metrics from payload, deduplicates on `(metric_name, recorded_at)`
- `WorkoutParser` — parses workouts from payload, deduplicates on Health Auto Export UUID

## Database tables

**Current:**
- `users` — Devise authentication (single user)
- `health_payloads` — raw webhook JSON, processing status
- `health_metrics` — non-workout readings, JSONB metadata, deduplicated on `(metric_name, recorded_at)`
- `workouts` — workout sessions, JSONB for type-specific data, deduplicated on Health Auto Export UUID

**Phase 4:**
- `strength_sessions` — exercises, sets, reps, weight, RPE

## Key decisions

- **Single-user app.** No multi-tenancy, no registration page. User is seeded.
- **No Action Mailer/Mailbox/Text/Cable.** Skipped at generation. Cable will be added back for Turbo Streams in Phase 2.
- **Health Auto Export** as the HealthKit bridge. No direct HealthKit integration — Apple has no server-side API.
- **Webhook uses bearer token auth**, not Devise sessions, so the iOS app can POST directly.
- **Solid Queue and Solid Cache share the primary database** (free Render tier has one Postgres instance).
