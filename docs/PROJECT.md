# Signals

An AI health coach that combines training plans, real-time HealthKit data, and LLM-powered guidance to provide context-aware accountability and insight.

## The problem

Fitness apps each see one slice — Runna knows your runs, Strong knows your lifts, MacroFactor knows your nutrition. None of them see the full picture. Chatting with an LLM about fitness lacks the rich data context to be genuinely useful, and conversations have a maximum length so coaching continuity is lost.

## The idea

Ingest health data from Apple HealthKit, overlay it against training and nutrition plans stored as markdown files, project your trajectory, and provide an LLM coach that has the full context of your fitness life.

### Core concepts

**Plan vs reality.** Your training plan says what you should do. HealthKit shows what you actually did. The delta between the two drives coaching.

**Markdown-first plans.** Training and nutrition plans live as `.md` files, created and edited through conversation with the LLM. No rigid schemas — the plan is a living document the AI can both read and write.

**LLM-assisted strength logging.** For workouts where HealthKit lacks detail (strength training), you log via natural conversation. The LLM knows today's plan and your history, so shorthand like "squats done, 5x5 at 102.5" is all you need.

**Daily briefing + nudges + chat.** The app pushes a morning briefing and event-driven nudges. A full-context chat is available for deep dives.

### The secret sauce: markdown + structured data

The most important design decision in Signals is what lives as natural language in markdown files versus what lives as structured data in Postgres. Getting this split right is what makes the LLM coaching genuinely useful rather than generic.

**Markdown files** are for anything that benefits from being human-readable, LLM-writable, and flexible in structure: training plans, nutrition goals, coaching notes, personal context ("I'm training for a half marathon in October", "my left ankle is injury-prone"). These are the things that give the LLM *understanding* — they're rich, contextual, and don't fit neatly into database columns. The LLM can read them natively in its context window and can edit them through conversation.

**Postgres** is for anything that needs to be queried, compared, trended, or deduplicated: health metrics, workout records, body composition history, strength session logs. These are the *facts* — timestamped, numeric, and accumulating over time. They power the projection engine and the plan-vs-reality comparisons.

The magic happens in the context assembly layer, where both sources merge into a single prompt. The LLM sees your plan (markdown) alongside what you actually did (database query results), and the gap between the two is where coaching lives. Neither source alone is sufficient — a plan without data is just a wishlist, and data without a plan is just numbers.

The exact boundary will evolve through use, but the guiding principle is: if you'd want an LLM to write or edit it, it's markdown. If you'd want to run a SQL query against it, it's Postgres.

## Tech stack

- **Backend:** Rails 8, PostgreSQL, Solid Queue
- **Frontend:** Hotwire (Turbo + Stimulus), Tailwind CSS
- **LLM:** GPT-5 Nano via OpenAI API (swappable — model is a config parameter)
- **Data pipeline:** Health Auto Export iOS app → REST API webhook
- **Auth:** Devise (email/password, single user)
- **Hosting:** Render (Rails + Postgres)

### Why GPT-5 Nano

At $0.05/M input tokens and $0.40/M output tokens with a 400K context window, the estimated monthly cost for a single user is well under $1. The tasks — daily briefing (summarisation), strength logging (extraction), nudges (classification) — are squarely in Nano's sweet spot. If deeper coaching conversations need more reasoning, the model can be swapped per interaction type.

### Why Health Auto Export

Apple HealthKit has no server-side API. Health Auto Export is a mature iOS app that reads HealthKit and pushes JSON to a REST API endpoint on a configurable schedule. Premium tier (required for REST API automation) is a one-off purchase of ~£6. Data freshness is typically 1-2 hours, faster when the phone is charging.

## Data pipeline

Health Auto Export sends JSON payloads via HTTP POST containing two main arrays: `metrics` (weight, heart rate, sleep, VO2max, steps, etc.) and `workouts` (with type-specific data for running, swimming, strength).

Running workouts include time-series heart rate, GPS route, distance over time, pace, cadence, and elevation. Swimming workouts additionally include SWOLF score, stroke style, stroke count, and lap length. Strength workouts from HealthKit only include duration and heart rate — detailed sets/reps/weight will be logged through the app's chat interface.

The webhook endpoint should log every raw payload before processing (for debugging and reprocessing), then parse and store the data with deduplication on metric name + timestamp.

Full JSON format documentation: https://github.com/Lybron/health-auto-export/wiki/API-Export---JSON-Format

An example payload is included in `docs/example_workout_payload.json`.

## Database design

Three tables for health data, plus a raw payload log:

**health_payloads** — every webhook POST logged with raw JSON, processing status, and error messages. Safety net for reprocessing if parsing logic changes.

**health_metrics** — all non-workout readings (weight, body fat, VO2max, resting HR, steps, sleep, HRV, etc.). Single table with a JSONB metadata column for type-specific fields (e.g. sleep phases, HR min/max). Deduplicated on `(metric_name, recorded_at)`.

**workouts** — workout sessions with common fields as proper columns (type, duration, distance, heart rate) and a JSONB metadata column for type-specific data (swimming SWOLF, running cadence, etc.). Time-series heart rate and GPS route stored as JSONB arrays. Deduplicated on the Health Auto Export UUID.

**strength_sessions** (Phase 4) — detailed strength workout logging with exercises, sets, reps, weight, and RPE. Linked to the corresponding HealthKit workout record for HR/duration data.

## Feature roadmap

### Phase 1 — Data pipeline (current)

Prove HealthKit data flows reliably into Postgres. Deploy to Render with Devise authentication so the dashboard and all future pages are secured from day one. The webhook endpoint uses bearer token auth (not Devise) so Health Auto Export can POST without a session. Build a simple Tailwind-styled dashboard showing recent data.

**Stage gate:** App deployed on Render behind Devise login. Health Auto Export configured and sending payloads on a schedule. Dashboard shows at least 24 hours of real data including weight, resting HR, sleep, and one workout. Deduplication works — resyncing the same time range doesn't create duplicates.

### Phase 2 — Training plans + Today view

Markdown-based training plans stored with version history. "Today" tab showing today's plan alongside actual data from HealthKit. Turbo Streams update the view as new data arrives.

### Phase 3 — LLM coaching

Context assembly service that builds the prompt from plan + recent data + projections + conversation history. Daily morning briefing generation. Chat interface with streaming responses. GPT-5 Nano as default model.

### Phase 4 — Projections + strength logging

Linear trend extrapolation for weight, body fat, VO2max. LLM-assisted strength workout logging via chat — the model parses natural language into structured set data using the training plan as context.

### Phase 5 — Nudges + notifications

Event-driven nudge detection after each data sync: missed workouts, PRs, trend shifts, sleep quality changes. Web Push API for browser notifications.

## Environment variables

- `DATABASE_URL` — Postgres connection string
- `RAILS_MASTER_KEY` / `SECRET_KEY_BASE` — Rails encryption
- `WEBHOOK_AUTH_TOKEN` — Bearer token protecting the webhook endpoint
- `OPENAI_API_KEY` — for GPT-5 Nano (Phase 3)

## Health Auto Export configuration

Once the app is deployed:

1. Install Health Auto Export on iPhone (Premium tier)
2. Create a REST API automation pointing to `https://your-app/api/v1/health_data`
3. Set format to JSON, Export Version 2
4. Add Authorization header with Bearer token
5. Select health metrics: weight, body fat, VO2max, heart rate, resting HR, HRV, steps, active energy, sleep analysis, dietary energy
6. Select workout types: running, swimming, strength training
7. Use Manual Export to send a test payload and verify data arrives
8. Enable background sync

Tips: keep the app in the dock so iOS doesn't kill it. Data syncs more reliably when charging. The home screen widget triggers a manual sync with one tap.
