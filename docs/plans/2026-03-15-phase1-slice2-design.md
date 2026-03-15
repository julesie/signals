# Phase 1, Slice 2: Webhook Endpoint, Health Data Tables, and Data Pipeline

**Date:** 2026-03-15
**Status:** Design approved
**Goal:** Ingest HealthKit data from Health Auto Export into Postgres, with a dashboard proving data flows end-to-end.

## Decisions

- **Full metric set from day one** — weight, body fat, VO2max, HR, resting HR, HRV, steps, active energy, sleep, dietary energy, plus running/swimming/strength workouts. The generic schema handles all types with no extra code.
- **Manual backfill + scheduled sync** — manual export covering March 1–today, then background sync going forward. Same webhook handles both.
- **Synchronous processing** — parse in the request, no background jobs. Single-user, small payloads, raw JSON always saved for reprocessing.
- **Service object pattern** — thin models, business logic in `app/services/`.
- **Basic but presentable dashboard** — cards for metrics, sleep, workouts, pipeline status. No charts yet.

## 1. Webhook endpoint

**Route:** `POST /api/v1/health_data`

**Controller:** `Api::V1::HealthDataController#create`

**Auth:** `before_action` checks `Authorization: Bearer <token>` against `ENV["WEBHOOK_AUTH_TOKEN"]`. Returns 401 if missing/wrong. Separate from Devise — no session required.

**Flow:**
1. Authenticate bearer token
2. Create `HealthPayload` record with raw JSON body and `status: "pending"`
3. Call `HealthDataProcessor.call(health_payload)`
4. Return `200 OK` with `{ status: "ok", metrics_count: N, workouts_count: N }` on success, or `422` with error details on failure

Raw payload is saved regardless of parse outcome.

## 2. Database tables

### health_payloads
- `id`, `raw_json` (jsonb), `status` (string: pending/processed/failed), `error_message` (text, nullable), `timestamps`
- No indexes beyond primary key

### health_metrics
- `id`, `metric_name` (string), `recorded_at` (datetime), `value` (decimal), `units` (string), `metadata` (jsonb, nullable), `timestamps`
- Unique index on `(metric_name, recorded_at)` for deduplication
- `value` holds the primary number: `qty` for simple metrics, `totalSleep` for sleep, `Avg` for heart rate
- `metadata` stores type-specific fields (sleep phases, HR min/max, etc.)

### workouts
- `id`, `external_id` (string — Health Auto Export UUID), `workout_type` (string), `started_at` (datetime), `ended_at` (datetime), `duration` (integer, seconds), `distance` (decimal, nullable), `distance_units` (string, nullable), `energy_burned` (decimal, nullable), `metadata` (jsonb), `timestamps`
- Unique index on `external_id` for deduplication
- `metadata` stores type-specific data: HR time-series, GPS route, elevation, cadence, speed, distance over time

## 3. Service objects

All in `app/services/`.

### HealthDataProcessor
- `HealthDataProcessor.call(health_payload)` — orchestrator
- Parses raw JSON, delegates to MetricsParser and WorkoutParser
- Wraps in a transaction — marks payload "failed" with error on failure
- Returns result with counts (metrics created/skipped, workouts created/skipped)

### MetricsParser
- Handles the `data.metrics` array
- For each metric's data points, builds `HealthMetric` records
- Extracts `value` intelligently by metric type
- Packs remaining fields into `metadata`
- Deduplicates via `find_or_create_by(metric_name:, recorded_at:)`

### WorkoutParser
- Handles the `data.workouts` array
- Extracts common columns (type, duration, distance, energy, start/end)
- Packs everything else into `metadata`
- Deduplicates via `find_or_create_by(external_id:)`

## 4. Dashboard

Existing `GET /` → `DashboardController#index` (behind Devise auth).

Four card sections, stacked vertically:

1. **Latest Metrics** — grid of stat cards for each metric type. Shows value, units, and relative time.
2. **Sleep** — latest sleep entry with total sleep, in-bed times, and core/deep/REM breakdown bar (Tailwind background segments, no JS).
3. **Recent Workouts** — last 5 workouts showing type, date, duration, distance, avg HR.
4. **Pipeline Status** — total payloads, last received timestamp, failed count.

Controller queries models directly — simple reads don't need a service object.

## 5. Testing

**Controller test** (`Api::V1::HealthDataControllerTest`):
- 401 with missing/invalid bearer token
- 200 with valid token and well-formed payload
- Creates HealthPayload record
- 422 on malformed data

**Service tests:**
- `HealthDataProcessorTest` — integration: full example payload → correct metrics/workouts created, payload marked processed
- `MetricsParserTest` — each metric type parsed correctly, deduplication works
- `WorkoutParserTest` — common fields extracted, metadata packed, deduplication on external_id

**Model tests:** Light validation checks.

**Dashboard test:** Integration test confirming page loads with data and shows expected sections.

**Fixture:** `docs/example_workout_payload.json` used directly in tests.

## Out of scope

- Charts / sparklines (Phase 2)
- Workout detail view
- Turbo Streams / live updates
- Background job processing
- OpenAI / LLM integration
