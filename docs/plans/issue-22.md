# Issue #22: Add metrics history pages with charting

**Issue:** [#22](https://github.com/julesie/signals/issues/22)
**Branch:** `issue-22-add-metrics-history-pages-with-charting`
**Status:** Executing
**Created:** 2026-03-29

---

## Problem Summary

Health metrics are only visible as latest-value snapshots on the dashboard. Users have no way to view historical data, spot trends, or drill into individual metrics over time. We need a `/metrics` index page showing the latest value per metric type, and a `/metrics/:metric_name` detail page with a Chart.js line chart and paginated history table.

## Key Findings

### Existing Patterns to Follow
- **WorkoutsController** provides the reference implementation for filtering (type + date range), pagination (20/page), and date defaults (last 30 days)
- **DashboardController** defines `METRIC_TYPES` constant (8 types + sleep) and queries latest metrics via `current_user.health_metrics.where(metric_name: name).order(recorded_at: :desc).first`
- All controllers inherit `before_action :authenticate_user!` from ApplicationController (Devise)

### HealthMetric Model
- Fields: `metric_name`, `recorded_at`, `value`, `units`, `metadata` (jsonb), `user_id`
- Unique index on `[user_id, metric_name, recorded_at]`
- Currently has no scopes — we'll add scopes for filtering

### Sleep Data Structure
- `value` = total sleep hours
- `metadata` contains: `core`, `deep`, `rem` (hours), `sleepStart`, `sleepEnd` (datetime strings), `inBed` (hours)
- Dashboard already has rendering logic for sleep breakdown we can reference

### JavaScript/Stimulus
- Importmap-based JS (no bundler) — `config/importmap.rb` pins Hotwired packages
- Stimulus controllers in `app/javascript/controllers/` auto-registered via `pin_all_from`
- Need to `bin/importmap pin chart.js` and create a `chart_controller.js`

### Views & Components
- `CardComponent` (flush option), `PageLayoutComponent` (max-width wrapper), `LoadingSpinnerComponent`
- Dark theme (zinc palette), Tailwind CSS
- Navigation in `application.html.erb` — Metrics link goes between "Workouts" and "Plan"

### Testing
- Minitest integration tests with Devise `sign_in` helper
- Fixtures for users; test data created in `setup` blocks
- Existing tests for dashboard and workouts cover auth, filtering, and response assertions

## Proposed Approach

### Routes
Add `resources :metrics, only: [:index, :show]` using `metric_name` as the param (e.g., `/metrics/weight`). Use a custom `param: :metric_name` or handle in the show action.

### HealthMetric Model
- Move `METRIC_TYPES` from DashboardController to `HealthMetric` as a class constant (include `sleep_analysis`)
- Add scopes: `by_name(name)`, `in_date_range(from, to)`

### MetricsController
- `index`: Query latest metric per type using `HealthMetric::METRIC_TYPES`. Sleep appears in the same grid as all other metrics (no special-casing). Render card grid.
- `show`: Accept `metric_name` param. Plot raw data points directly on chart (upsert means one row per metric per timestamp — no aggregation needed). Apply date range filtering (default 30 days) and pagination (20/page) for the table.

### Chart.js Integration
- `bin/importmap pin chart.js` to add the dependency
- Create `chart_controller.js` Stimulus controller that reads JSON data from a `data-chart-data-value` attribute and renders a line chart on a `<canvas>` target
- Pass chart data as JSON from the controller/view (dates as labels, values as data points)

### Views
- **Index** (`metrics/index.html.erb`): PageLayoutComponent wrapping a card grid. Each card shows metric name, latest value, units, time ago. Each card links to `/metrics/:metric_name`.
- **Show** (`metrics/show.html.erb`): PageLayoutComponent with date filter form at top, Chart.js canvas in a card, then paginated history table below. Sleep rows have an inline toggle (Stimulus) to expand and show the full breakdown (stages, bed/wake times).

### Dashboard Linking
- Wrap existing "Latest Metrics" cards with links to `/metrics/:metric_name`
- Wrap "Sleep" section with link to `/metrics/sleep_analysis`

### Navigation
Add "Metrics" link in `application.html.erb` nav between "Workouts" and "Plan".

### Tests
Integration tests covering:
- Index page renders all metric types with latest values
- Show page renders chart and table for a given metric
- Date range filtering works
- Pagination works
- Sleep breakdown displays correctly
- Auth required (redirect when signed out)

## Step-by-Step Tasks

- [ ] 1. Add Chart.js via importmap (`bin/importmap pin chart.js`)
- [ ] 2. Move `METRIC_TYPES` to HealthMetric model (include sleep_analysis), add scopes (`by_name`, `in_date_range`), update DashboardController to reference new location
- [ ] 3. Add routes: `resources :metrics, only: [:index, :show], param: :metric_name`
- [ ] 4. Create MetricsController with `index` and `show` actions (filtering, pagination)
- [ ] 5. Create metrics index view (card grid with latest values, linked cards)
- [ ] 6. Create chart Stimulus controller (`chart_controller.js`)
- [ ] 7. Create metrics show view (date filter + line chart + paginated table)
- [ ] 8. Add sleep breakdown inline toggle (Stimulus) for sleep_analysis rows on show page
- [ ] 9. Add dashboard linking (metric cards → `/metrics/:metric_name`, sleep → `/metrics/sleep_analysis`)
- [ ] 10. Add "Metrics" link to application layout nav
- [ ] 11. Write integration tests for metrics pages
- [ ] 12. Verify all tests pass and manually smoke test

## Open Questions / Unknowns

All resolved:
- ~~METRIC_TYPES location~~ → Move to HealthMetric model as class constant
- ~~Sleep on index page~~ → Same grid, same card format as other metrics
- ~~Chart aggregation~~ → Plot raw data points (upsert means one per timestamp)
- ~~Dashboard linking~~ → Yes, wrap metric cards with links to detail pages
- ~~Sleep breakdown UX~~ → Inline toggle via Stimulus

---

*This plan is a living document — update it as understanding evolves.*
