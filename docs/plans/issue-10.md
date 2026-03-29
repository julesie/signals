# Issue #10: Add user notes to workout cards

**Issue:** [#10](https://github.com/julesie/signals/issues/10)
**Branch:** `issue-10-add-user-notes-to-workout-cards`
**Status:** Executing
**Created:** 2026-03-29

---

## Problem Summary

Workouts currently display only raw health data (type, duration, distance, HR, energy) with no way for the user to add personal context. Notes like "knee felt tight" or "easy recovery pace" would make workout history more meaningful and give the LLM better context when generating daily suggestions and plan adherence assessments. This is the first user-editable field on workouts — all other data comes from the HealthKit API.

## Key Findings

### Current Architecture
- **Workout model** (`app/models/workout.rb`): validates `external_id`, `workout_type`, `started_at`, `ended_at`, `duration`. No user-editable fields.
- **CardComponent** (`app/components/card_component.rb`): generic wrapper, not workout-specific. Workout rendering is inline in views.
- **Dashboard view** (`app/views/dashboard/index.html.erb:18-47`): renders today's workouts in CardComponents.
- **Workouts index** (`app/views/workouts/index.html.erb:35-139`): mobile (stacked cards) and desktop (table) layouts with filtering/pagination.
- **Routes** (`config/routes.rb`): only `resources :workouts, only: [:index]` — no update action exists.

### LLM Integration
- **Plan suggestion generator** (`app/services/plan_suggestion_generator.rb:65-77`): formats workouts as `"- date, type, duration, distance, energy"` for last 7 days + today.
- **Plan adherence generator** (`app/services/plan_adherence_generator.rb:67-77`): similar format, includes 7-day and 30-day windows.
- Neither currently includes any notes field.

### Frontend Patterns
- Turbo Rails + Stimulus available but minimal Stimulus usage.
- No existing modal pattern in the codebase — dynamic content uses Turbo frames with lazy loading.
- Tailwind CSS for styling.

### Test Patterns
- Minitest with fixtures, not RSpec.
- Workout model tests: validation-focused (`test/models/workout_test.rb`).
- Generator tests: mock LLM, assert context includes workout data (`test/services/plan_*_generator_test.rb`).
- Integration tests: Devise helpers, assert response body content (`test/integration/workouts_test.rb`).

## Design Decisions

1. **Auth**: No user scoping — Devise `authenticate_user!` is sufficient. User-scoping deferred to [#11](https://github.com/julesie/signals/issues/11).
2. **Turbo response**: Simple `redirect_back(fallback_location: workouts_path)` after save. No turbo_stream complexity — this is a low-frequency action.
3. **Shared partial**: Extract one `_workout_card_content.html.erb` partial used by both dashboard and workouts index mobile cards. The dashboard currently omits avg HR — unify both to show the full data set (type, time, duration, distance, avg HR, energy, note).
4. **Date/time display**: Card always shows time only (`%-I:%M %p`). Workouts index mobile view groups cards under day headings (e.g. "Mon, Mar 23"). Desktop table keeps the full date+time column as-is — no grouping.
5. **Dialog**: Single page-level `<dialog>` rendered via a shared partial (`workouts/_notes_dialog.html.erb`), included at the bottom of dashboard and workouts index views.
6. **Stimulus controller**: `notes_modal_controller` — pen icon has `data-*` attributes (workout ID, current note, form action URL). On click, controller populates the dialog's textarea and form action, then calls `showModal()`. Also handles live character counter.
7. **Note preview on cards**: New row below the stats. Truncated to ~60 chars with ellipsis. Pen icon sits to the right, always visible (even when no note exists).
   ```
   Outdoor Run                    2:30 PM
   32m  5.2 km  142 bpm  320 kcal
   "Knee felt tight on hills..."     [pen]
   ```
8. **Desktop table**: Add a Notes column. Pen icon always shown. Hover shows note as tooltip when one exists. Click opens the edit modal.
9. **LLM notes**: Only appended to workout lines when present. Format: `— "note text"` at the end of the line. No indication for workouts without notes.
10. **Column type**: `text` (Postgres `text`, not `varchar`). 280-char limit enforced in model validation and UI only.

## Proposed Approach

### Database
Add a nullable `notes` text column to workouts via migration.

### Model
Add `validates :notes, length: { maximum: 280 }, allow_blank: true` to Workout.

### Routes & Controller
Add `update` action to workouts resource: `resources :workouts, only: [:index, :update]`. The update action permits only `notes` via strong params, saves, and `redirect_back`.

### UI — Shared workout card partial
Extract `app/views/workouts/_workout_card_content.html.erb` from the existing dashboard and workouts index mobile markup. Unify to show: workout type, time, duration, distance, avg HR, energy, note preview + pen icon.

### UI — Day grouping on workouts index
Group `@workouts` by date on the mobile view, rendering a date heading (`%a, %b %-d`) before each day's cards. Desktop table unchanged.

### UI — Notes dialog
Single `<dialog>` in `app/views/workouts/_notes_dialog.html.erb`, rendered at page bottom on dashboard and workouts index. Contains a `<form>` with `<textarea>` (maxlength=280), live character counter, and save/cancel buttons. Form action set dynamically by Stimulus.

### Stimulus controller
`notes_modal_controller` handles:
- Opening the dialog (populate textarea + form action from `data-*` attributes, call `showModal()`)
- Live character counter on textarea input
- Closing the dialog on cancel

### LLM Prompt Integration
In both generators' `format_workouts` and `format_todays_workouts`, append `— "note"` when `w.notes.present?`:
```
- Mon Mar 23, Running, 32 min, 5.2 km, 320 kcal — "knee felt tight on hills"
```

## Step-by-Step Tasks

### Batch 1: Database & Model
- [ ] 1. Migration: add `notes` (text, nullable) to workouts table
- [ ] 2. Model: add length validation for notes
- [ ] 3. Model test: validate 280-char limit, valid with blank/nil notes

### Batch 2: Routes & Controller
- [ ] 4. Routes: add `update` to workouts resource
- [ ] 5. Controller: add `update` action with strong params (notes only), `redirect_back`
- [ ] 6. Integration test: PATCH workout with note, assert persistence and redirect

### Batch 3: Frontend — Stimulus & Dialog
- [ ] 7. Stimulus controller: `notes_modal_controller` (open/close dialog, populate form, character counter)
- [ ] 8. Dialog partial: `workouts/_notes_dialog.html.erb` with form, textarea, counter, save/cancel

### Batch 4: View Updates
- [ ] 9. Shared partial: extract `workouts/_workout_card_content.html.erb` with note preview + pen icon
- [ ] 10. Update dashboard view to use the shared partial
- [ ] 11. Update workouts index mobile view: day-group headings + shared partial
- [ ] 12. Update workouts index desktop table: add Notes column with pen icon + tooltip
- [ ] 13. Render `_notes_dialog` partial at bottom of dashboard and workouts index views

### Batch 5: LLM Integration
- [ ] 14. Update `format_workouts` and `format_todays_workouts` in PlanSuggestionGenerator to include notes
- [ ] 15. Update `format_workouts` in PlanAdherenceGenerator to include notes
- [ ] 16. Generator tests: assert notes appear in LLM context when present

## Open Questions / Unknowns

All resolved. See Design Decisions above.

---

*This plan is a living document — update it as understanding evolves.*
