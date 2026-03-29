# Today Tab Redesign & Workouts History

## Summary

Redesign the homepage into a "Today-centric" view with auto-generated AI suggestions and plan adherence tracking, and move workout history browsing to a dedicated `/workouts` page.

## Motivation

The current homepage displays recent workouts alongside metrics and sleep data, mixing "today" context with historical browsing. Separating these concerns gives the homepage a clearer purpose — what's happening today and how you're tracking — while providing a better home for exploring workout history with filters and pagination.

## Today Page (`/`, `dashboard#index`)

### Layout (top to bottom)

1. **Today's Suggestion** (Turbo Frame, lazy-loaded)
2. **Today's Workouts** (server-rendered, no lazy-load)
3. **Plan Adherence** (Turbo Frame, lazy-loaded)
4. **Latest Metrics** (unchanged from current)
5. **Sleep** (unchanged from current)
6. **Sync/Pipeline Status** (unchanged from current)

### Today's Suggestion

- Rendered inside a `<turbo-frame id="suggestion" src="/dashboard/suggestion">` with a loading spinner placeholder.
- **Endpoint:** `GET /dashboard/suggestion` -> `dashboard#suggestion`
- **First-visit-of-the-day logic:** Check `plan.suggestion_generated_at` (existing column). If it's from today, return cached `plan.daily_suggestion` immediately. If not, call the AI service, persist the result and timestamp, return the HTML fragment.
- **Workout-aware:** The AI prompt receives today's completed workouts (`Workout.where(started_at: Date.current.all_day)`). If workouts exist, the suggestion acknowledges them and suggests complementary activity or rest rather than an additional full workout. If none exist, it suggests what to do based on the plan.
- Subsequent visits the same day render instantly from cache (no spinner).
- Retains the existing "Regenerate" button which forces a fresh AI call regardless of cache. The regenerate button POSTs to `/dashboard/suggestion` and returns a Turbo Frame response, keeping the interaction within the frame (no full-page redirect).
- **Error handling:** If the AI call fails, the frame renders an error message ("Could not generate suggestion. Try again later.") with a retry button, replacing the spinner.

### Today's Workouts

- Queries `Workout.where(started_at: Date.current.all_day)`.
- Displays as simple cards: workout type, duration, distance (if present), energy burned.
- **Empty state:** "No workouts recorded today."
- Not lazy-loaded — this is a fast DB query rendered with the initial page load.
- Includes a "View all workouts" link to `/workouts` for discoverability.

### Plan Adherence

- Rendered inside a `<turbo-frame id="adherence" src="/dashboard/adherence">` with a loading spinner placeholder.
- **Endpoint:** `GET /dashboard/adherence` -> `dashboard#adherence`
- **Two parts:**

#### AI Narrative

- New service: `PlanAdherenceGenerator`
- **Inputs:** plan content, workouts from last 7 days, workouts from last 30 days, active energy metrics.
- **Output:** Short narrative with two paragraphs — one for the 7-day view, one for the 30-day view.
- **Caching:** Persisted in `plan.adherence_summary` with `plan.adherence_summary_generated_at` timestamp. Same first-visit-of-the-day cache logic as the suggestion.
- **Regenerate button:** POSTs to `/dashboard/adherence`, forces a fresh AI call, returns Turbo Frame response.
- **Error handling:** Same pattern as suggestion — frame renders error message with retry button on failure.

#### Active Calories Bar Chart

- Queries `HealthMetric.where(metric_name: "active_energy")` for the last 7 days.
- Groups by date, sums values per day.
- Renders 7 bars as `div` elements with percentage heights. Max height normalized to the highest value or 500kcal, whichever is greater.
- 500kcal goal line rendered as an absolute-positioned border. This is a hardcoded constant for now (single-user app).
- Pure HTML/CSS, no JavaScript charting library.
- Multiple `active_energy` readings per day are possible; summing by date handles this correctly.
- Rendered inline with the adherence frame response (not a separate lazy-load).

### Loading Spinner

- New `LoadingSpinnerComponent` (ViewComponent).
- Centered animated CSS spinner with optional text (e.g., "Generating suggestion...").
- Styled for dark theme: `zinc-400` spinner on `zinc-800` background.

## Workouts History Page (`/workouts`)

### Route & Controller

- **Route:** `resources :workouts, only: [:index]`
- **Controller:** `WorkoutsController#index`

### Filters

- **Workout type:** `<select>` dropdown populated from `Workout.distinct.pluck(:workout_type)`.
- **Date range:** Two date inputs (from/to). Defaults to last 30 days when no filter is applied.
- Filters submit as GET params (standard form submission, no JS). URLs are shareable/bookmarkable.

### Display

- Reuses the responsive layout pattern from the current homepage workout section:
  - **Mobile:** Stacked cards.
  - **Desktop:** Table with columns — type, date, duration, distance, avg HR, energy burned.
- Paginated (Pagy or simple limit/offset) rather than capped at 5.

### Navigation

- "Workouts" link added to the global nav bar alongside "Plan".

## Data Model Changes

### Plan model — add columns

| Column | Type | Purpose |
|--------|------|---------|
| `adherence_summary` | `text` | Cached AI adherence narrative |
| `adherence_summary_generated_at` | `datetime` | Cache check for first-visit-of-the-day adherence |

The existing `daily_suggestion` column stores the suggestion text and `suggestion_generated_at` tracks when it was generated. No new suggestion columns needed.

### No new tables

- Active calories bar chart reads from `health_metrics` (metric_name: "active_energy").
- Today's workouts reads from `workouts`.

### No changes to Workout or HealthMetric models

## Technical Approach

### Routes

```ruby
# Dashboard Turbo Frame endpoints
get "dashboard/suggestion", to: "dashboard#suggestion"
post "dashboard/suggestion", to: "dashboard#regenerate_suggestion"
get "dashboard/adherence", to: "dashboard#adherence"
post "dashboard/adherence", to: "dashboard#regenerate_adherence"

# Workouts
resources :workouts, only: [:index]
```

### Turbo Frames

- First use of Turbo in this app. Turbo is already available via importmaps.
- Two lazy-loaded frames: `suggestion` and `adherence`.
- Each frame has a `src` attribute pointing to a dedicated controller action.
- The frame initially contains a `LoadingSpinnerComponent` which is replaced when the response arrives.
- Regenerate buttons POST to the same path and return a Turbo Frame response (no full-page redirect).

### Scoping Note

This is a single-user app. Workout and HealthMetric queries are unscoped (no `user_id` filtering). Plan is scoped to `current_user` via `has_one :plan`.

### Layout Reordering

The current dashboard renders: suggestion, sync status, metrics, sleep, workouts, pipeline status. This redesign deliberately reorders to: suggestion, today's workouts, adherence, metrics, sleep, sync/pipeline status (consolidated).

### New Files

| File | Purpose |
|------|---------|
| `app/controllers/workouts_controller.rb` | Workouts index with filters |
| `app/views/workouts/index.html.erb` | Filterable, paginated workout list |
| `app/services/plan_adherence_generator.rb` | AI adherence narrative service |
| `app/components/loading_spinner_component.rb` | Spinner ViewComponent |
| `app/components/loading_spinner_component.html.erb` | Spinner template |
| `app/views/dashboard/suggestion.html.erb` | Turbo Frame response for suggestion |
| `app/views/dashboard/adherence.html.erb` | Turbo Frame response for adherence |
| `db/migrate/..._add_adherence_fields_to_plans.rb` | Migration for new Plan columns |

### Modified Files

| File | Change |
|------|--------|
| `config/routes.rb` | Add workouts resource, dashboard member routes |
| `app/controllers/dashboard_controller.rb` | Add `suggestion` and `adherence` actions, add today's workouts query, remove recent workouts query |
| `app/views/dashboard/index.html.erb` | Replace recent workouts with today's workouts, add Turbo Frames, add adherence section |
| `app/views/layouts/application.html.erb` | Add "Workouts" nav link |
| `app/services/plan_suggestion_generator.rb` | Pass today's workouts to AI prompt |
