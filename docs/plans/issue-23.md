# Issue #23: Add food logging with LLM-powered macro estimation

**Issue:** [#23](https://github.com/julesie/signals/issues/23)
**Branch:** `issue-23-add-food-logging-with-llm-macro-estimation`
**Status:** Done
**Created:** 2026-03-29

---

## Problem Summary

MacroFactor is clunky and doesn't sync detailed macro data to Apple Health. Since Signals already tracks health metrics and workouts, adding food logging makes it the single source of truth for daily nutrition. The user describes what they ate in free text, an LLM estimates macros, and the entry is saved immediately. Frequency-based quick-add suggestions support the user's repetitive diet by enabling one-tap re-logging. A daily view shows entries grouped by mealtime with progress against calorie/protein targets.

## Key Findings

### Existing Patterns to Follow

- **Models**: All scoped to `user_id` with `belongs_to :user` + `dependent: :destroy`. Validations on required fields. JSONB metadata columns for flexible data. Uniqueness constraints where needed.
- **LLM integration**: `PlanChatService` pattern — class method `.call(args)` returning a `Result` struct (`success`, `response/suggestion`, `error`). Uses `RubyLLM.chat` with model from `ENV["LLM_MODEL"]` (default `gpt-5-nano`). System prompt + user prompt.
- **Controllers**: Inherit `ApplicationController`, `before_action :authenticate_user!`, scope all queries via `current_user`. RESTful + custom actions. Turbo-compatible redirects with notice/alert.
- **Views**: Tailwind dark mode (zinc palette), ViewComponent for cards/layout, Turbo Frames for lazy loading, Stimulus controllers for interactivity (modals, charts, toggles). Responsive grids. ERB templates.
- **Tests**: Minitest with fixtures, integration tests with `Devise::Test::IntegrationHelpers`, service tests stub `RubyLLM.chat`.
- **Routes**: RESTful resources, singular `resource :plan`, custom member/collection actions via `post`/`get`.

## Design Decisions

### Data Model (3 tables)

**`foods` table** — canonical items with macros:
| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| user_id | bigint | FK, not null, indexed |
| description | text | not null |
| kcal | decimal | not null |
| protein | decimal(5,1) | grams |
| carbs | decimal(5,1) | grams |
| fat | decimal(5,1) | grams |
| fibre | decimal(5,1) | grams |
| alcohol | decimal(5,1) | grams, default 0 |

**`food_logs` table** — the event of eating, with stamped macros:
| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| user_id | bigint | FK, not null, indexed |
| food_id | bigint | FK, not null |
| consumed_at | datetime | not null, default now |
| mealtime | string | enum: breakfast, lunch, dinner, snack |
| kcal | decimal | stamped from food at log time |
| protein | decimal(5,1) | stamped |
| carbs | decimal(5,1) | stamped |
| fat | decimal(5,1) | stamped |
| fibre | decimal(5,1) | stamped |
| alcohol | decimal(5,1) | stamped |
| user_id + consumed_at | index | for daily queries |

**`nutrition_profiles` table** — daily targets:
| Column | Type | Notes |
|--------|------|-------|
| id | bigint | PK |
| user_id | bigint | FK, not null, unique |
| calorie_target | integer | not null, default 1600 |
| protein_target | integer | not null, default 100 |

Net carbs = `carbs - fibre` (computed, not stored).

Editing a food log entry updates both the `food_log` stamped macros AND the `food` canonical macros (user doesn't think in terms of two tables).

### No Explicit Favourites

Favourites are derived from frequency (`COUNT(food_logs) GROUP BY food_id`). No `favourite` boolean, no toggle action. Simpler model, same UX outcome.

### Mealtime Auto-Suggest

- Before 11:30 = breakfast
- 11:30 - 16:30 = lunch
- After 16:30 = dinner
- Select box with: breakfast, lunch, dinner, snack

### UX Flows

**Dashboard → Add Food:**
- Top section of dashboard shows nutrition summary card: kcal + protein progress bars vs targets
- Prominent "Add food" button links to `/food_logs/new`
- Tapping the card itself links to `/food_logs` (daily view)
- "Food" added to navbar beside Workouts and Metrics

**`/food_logs/new` — Log a meal:**
- Two quick-add sections filtered by auto-suggested mealtime:
  - **Recent**: 5 most recent entries at this mealtime
  - **Favourites**: 5 most frequent entries at this mealtime (frequency-derived)
  - Can overlap — same items may appear in both
- Each quick-add item has two actions:
  - **Tap to clone**: instant save, stamps current `food` macros into new `food_log`, no LLM call. Stay on page with success flash.
  - **Secondary action ("Re-estimate")**: pre-fills text field with description for LLM re-estimation
- Free-text form: text area + mealtime select + consumed_at hour dropdown (24h clock)
  - Submit → Turbo Frame wraps form area, shows spinner while LLM estimates
  - Creates `food` + `food_log`, stays on page with success flash
  - User can batch-log multiple items (e.g. eggs, toast, coffee for breakfast)

**`/food_logs` — Daily view:**
- Date picker, defaults to today
- Top: progress bars for kcal + protein vs targets, summary line for fat + net carbs + fibre (informational, no targets). "Edit targets" link → nutrition profile settings.
- Entries grouped by mealtime in order: breakfast → lunch → dinner → snack
- Each mealtime group has subtotal row
- Each entry row: description (left) | kcal, protein, net carbs (right). Tap to edit.
- Edit form: updates both `food_log` stamps and `food` canonical macros

**Nutrition profile settings** (`/nutrition_profile/edit`):
- Accessed via link near progress bars on daily view
- Simple form: calorie_target, protein_target

### LLM Integration

**FoodEstimationService** following `PlanChatService` pattern:
- Input: free-text description
- System prompt: estimate macros, return ONLY valid JSON `{"kcal": number, "protein": number, "carbs": number, "fat": number, "fibre": number, "alcohol": number}`. All values in grams except kcal. Assume typical single serving if portion unclear. Never ask clarifying questions.
- Parse JSON response, return Result struct
- On error: flash error, don't save anything, user retries. Matches existing error pattern.
- Model: `ENV["LLM_MODEL"]` / `gpt-5-nano`

### Consumed At

- Defaults to current hour
- Simple hour dropdown, 24-hour clock
- Stored as full datetime (today's date + selected hour)

## Proposed Approach

Build in vertical slices, each independently deployable:

### Slice 1: Data layer
- Migration for `foods`, `food_logs`, and `nutrition_profiles` tables
- `Food`, `FoodLog`, and `NutritionProfile` models with validations, associations, scopes
- Fixtures and model tests

### Slice 2: Nutrition profile settings
- `NutritionProfilesController` with edit/update
- Settings UI (simple form)
- Route + integration test

### Slice 3: FoodEstimationService
- LLM service following PlanChatService pattern
- System prompt for macro estimation, structured JSON output
- JSON response parsing with error handling
- Service tests with stubbed LLM

### Slice 4: Food logging — new page + create flow
- `FoodLogsController` with new/create actions
- `/food_logs/new` page with:
  - Quick-add sections (recent 5 + frequent 5 for current mealtime)
  - Free-text form with mealtime select + hour dropdown
  - Turbo Frame for LLM estimation (spinner while processing)
  - Clone action for quick-adds (no LLM)
  - Re-estimate action (pre-fill text field)
  - Stay on page after each log with success flash
- Integration tests

### Slice 5: Daily view + edit/delete
- `food_logs#index` with date picker, defaults to today
- Progress bars (kcal/protein vs targets) + summary line (fat, net carbs, fibre)
- Entries grouped by mealtime (breakfast → lunch → dinner → snack) with subtotals
- Entry rows: description | kcal, protein, net carbs
- Edit action: updates food_log stamps + food canonical macros
- Delete action
- Integration tests

### Slice 6: Dashboard + navbar integration
- Nutrition summary card at top of dashboard (kcal/protein progress + "Add food" button)
- Card links to `/food_logs` daily view
- "Food" in navbar beside Workouts and Metrics

## Step-by-Step Tasks

### Batch 1: Data layer (Slice 1)
- [ ] 1.1 Create migration for `foods` table
- [ ] 1.2 Create migration for `food_logs` table
- [ ] 1.3 Create migration for `nutrition_profiles` table
- [ ] 1.4 Create `Food` model with validations, associations, scopes
- [ ] 1.5 Create `FoodLog` model with validations, associations, mealtime enum, scopes
- [ ] 1.6 Create `NutritionProfile` model with validations, associations
- [ ] 1.7 Add `has_many :foods`, `has_many :food_logs`, `has_one :nutrition_profile` to User
- [ ] 1.8 Create fixtures for foods, food_logs, nutrition_profiles
- [ ] 1.9 Write model tests
- [ ] 1.10 Run migrations and verify tests pass

### Batch 2: FoodEstimationService + Nutrition profile settings (Slices 2 & 3)
- [ ] 2.1 Create `FoodEstimationService` with system prompt, JSON parsing, Result struct
- [ ] 2.2 Write service tests with stubbed LLM
- [ ] 2.3 Create `NutritionProfilesController` with edit/update
- [ ] 2.4 Create nutrition profile edit view
- [ ] 2.5 Add route for `resource :nutrition_profile`
- [ ] 2.6 Write integration test for nutrition profile

### Batch 3: Food logging new page + create flow (Slice 4)
- [ ] 3.1 Create `FoodLogsController` with new, create, quick_add actions
- [ ] 3.2 Add routes for food_logs
- [ ] 3.3 Create `/food_logs/new` view with quick-add sections (recent + frequent)
- [ ] 3.4 Create free-text form with mealtime select + hour dropdown
- [ ] 3.5 Implement Turbo Frame for LLM estimation flow
- [ ] 3.6 Implement clone action for quick-adds
- [ ] 3.7 Implement re-estimate action (pre-fill text field)
- [ ] 3.8 Add mealtime auto-suggest logic
- [ ] 3.9 Write integration tests for create flows

### Batch 4: Daily view + edit/delete (Slice 5)
- [ ] 4.1 Add index action to FoodLogsController with date filtering
- [ ] 4.2 Create daily view with progress bars and summary line
- [ ] 4.3 Group entries by mealtime with subtotals
- [ ] 4.4 Add edit/update actions (updates food_log + food)
- [ ] 4.5 Add delete action
- [ ] 4.6 Add "Edit targets" link to nutrition profile
- [ ] 4.7 Write integration tests for daily view, edit, delete

### Batch 5: Dashboard + navbar integration (Slice 6)
- [ ] 5.1 Add nutrition summary card to dashboard (progress bars + "Add food" button)
- [ ] 5.2 Add "Food" link to navbar
- [ ] 5.3 Load nutrition data in DashboardController
- [ ] 5.4 Write integration tests for dashboard nutrition section

## Open Questions / Unknowns

All resolved — see Design Decisions above.

---

*This plan is a living document — update it as understanding evolves.*
