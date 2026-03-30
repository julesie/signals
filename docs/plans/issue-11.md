# Issue #11: Scope workouts and health metrics to the authenticated user

**Issue:** [#11](https://github.com/julesie/signals/issues/11)
**Branch:** `issue-11-scope-workouts-health-metrics-to-user`
**Status:** Done
**Created:** 2026-03-29

---

## Problem Summary

Workouts and health metrics have no `user_id` column — all queries are global. Any authenticated user can view and edit all records. The LLM generators (plan suggestions, adherence) mix data from all users. The API webhook ingestion creates records with no user association. The Plan model already follows the correct pattern (`belongs_to :user`); Workout and HealthMetric need the same treatment.

## Key Findings

### What's already scoped
- `Plan` has `belongs_to :user`, `user_id` FK, uniqueness constraint — correct pattern to follow
- `PlansController` uses `current_user.plan` — good

### What's unscoped (the problem)
- **WorkoutsController#index** — `Workout.order(started_at: :desc)` returns all users' workouts
- **WorkoutsController#update** — `Workout.find(params[:id])` can edit any user's workout
- **DashboardController#index** — `Workout.where(started_at: Date.current.all_day)` and `HealthMetric.where(metric_name:...)` are global
- **DashboardController#load_active_calories** — global HealthMetric query
- **PlanSuggestionGenerator** — receives `@plan` (has user) but queries `Workout.where(...)` and `HealthMetric.where(...)` globally
- **PlanAdherenceGenerator** — same issue
- **MetricsParser** — uniqueness by `(metric_name, recorded_at)` only; two users with same metric at same time = overwrite
- **WorkoutParser** — no user context

### API ingestion flow
```
Apple HealthKit → Webhook → Api::V1::HealthDataController (token auth)
  → HealthPayload.create! → HealthDataProcessor → MetricsParser + WorkoutParser
```
- Single global `WEBHOOK_AUTH_TOKEN`, no user identifier
- HealthPayload has no user_id
- Parsers create records with no user association

### Files that need changes
| File | Change |
|------|--------|
| Migration (new) | Add `user_id` FK to `workouts` and `health_metrics`, update uniqueness indexes |
| `app/models/user.rb` | Add `has_many :workouts` and `has_many :health_metrics` |
| `app/models/workout.rb` | Add `belongs_to :user` |
| `app/models/health_metric.rb` | Add `belongs_to :user`, update uniqueness scope |
| `app/models/health_payload.rb` | Add `belongs_to :user` |
| `app/controllers/workouts_controller.rb` | Scope all queries through `current_user.workouts` |
| `app/controllers/dashboard_controller.rb` | Scope workout/metric queries through `current_user` |
| `app/controllers/api/v1/health_data_controller.rb` | Resolve user from token, pass to processor |
| `app/services/health_data_processor.rb` | Accept and pass user context |
| `app/services/metrics_parser.rb` | Accept user, create records with `user_id` |
| `app/services/workout_parser.rb` | Accept user, create records with `user_id` |
| `app/services/health_data_reprocessor.rb` | Scope delete/recreate to user |
| `app/services/csv_importer.rb` | Accept user, scope queries through user associations |
| `db/seeds.rb` | Pass user to CsvImporter |
| `app/services/plan_suggestion_generator.rb` | Scope queries through `@plan.user` |
| `app/services/plan_adherence_generator.rb` | Scope queries through `@plan.user` |
| Tests | Add cross-user isolation tests, update fixtures |

## Proposed Approach

### 1. Migration
- Add `user_id` (bigint, NOT NULL, FK) to `workouts` and `health_metrics`
- Add `user_id` (bigint, FK) to `health_payloads`
- Backfill existing records to `User.find_by!(email: 'jules@julescoleman.com')`
- Update unique indexes: `health_metrics` uniqueness becomes `(user_id, metric_name, recorded_at)`, `workouts` keeps `external_id` unique (Apple HealthKit IDs are globally unique)
- Add composite indexes for query performance: `(user_id, started_at)` on workouts, `(user_id, metric_name, recorded_at)` on health_metrics

### 2. Models
- Add `belongs_to :user` on Workout, HealthMetric, HealthPayload
- Add `has_many` associations on User with `dependent: :delete_all`
- Update HealthMetric uniqueness validation to scope by `user_id`

### 3. Controllers
- All Workout/HealthMetric queries go through `current_user.workouts` / `current_user.health_metrics`
- WorkoutsController#update scoped: `current_user.workouts.find(params[:id])`

### 4. API ingestion — hardcode to existing user for now
- After authenticating the global webhook token, look up the single user (`jules@julescoleman.com`) and associate incoming data with them
- Pass user through: `HealthDataProcessor → MetricsParser/WorkoutParser`
- HealthPayload gets associated with user
- Per-user webhook tokens deferred until a second user is needed

### 5. LLM generators
- Both generators already receive `@plan` which has `@plan.user`
- Change queries to `@plan.user.workouts.where(...)` and `@plan.user.health_metrics.where(...)`

### 6. HealthDataReprocessor
- Group payloads by `user_id`, delete only that user's workouts/metrics, replay their payloads

### 7. CsvImporter
- Accept `user:` keyword arg, scope all queries through `user.workouts` / `user.health_metrics`
- Update `seeds.rb` to pass user

## Step-by-Step Tasks

- [ ] 1. Migration: add `user_id` to workouts, health_metrics, health_payloads; backfill to `jules@julescoleman.com`; add NOT NULL + indexes
- [ ] 2. Models: add associations (`belongs_to :user`, `has_many` with `dependent: :delete_all`) and update validations
- [ ] 3. Update API controller to look up `jules@julescoleman.com` and pass user to processor
- [ ] 4. Thread user through HealthDataProcessor → MetricsParser → WorkoutParser
- [ ] 5. Update CsvImporter to accept user, scope queries; update seeds.rb
- [ ] 6. Update HealthDataReprocessor to scope deletes per-user
- [ ] 7. Scope WorkoutsController queries to current_user
- [ ] 8. Scope DashboardController queries to current_user
- [ ] 9. Scope PlanSuggestionGenerator and PlanAdherenceGenerator to plan's user
- [ ] 10. Update tests: fixtures, cross-user isolation, API tests

## Open Questions / Unknowns

All resolved during alignment:
- ~~Per-user webhook tokens~~ Hardcode to `jules@julescoleman.com` for now. Revisit if a second user is added.
- ~~HealthDataReprocessor scope~~ Scope deletes per-user: group payloads by user, delete that user's records, replay.
- ~~External ID uniqueness~~ Keep globally unique (Apple HealthKit UUIDs are globally unique).
- ~~Migration strategy~~ Single migration (data volume is small).
- ~~Backfill target~~ Use `User.find_by!(email: 'jules@julescoleman.com')`, not `User.first`.
- ~~dependent option~~ Use `delete_all` not `destroy` (no callbacks on these models).
- ~~CsvImporter~~ Added to scope — accept user, pass through seeds.rb.

---

*This plan is a living document — update it as understanding evolves.*
