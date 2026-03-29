# Issue #4: Add fitness plan with AI-powered daily activity suggestions

**Issue:** [#4](https://github.com/julesie/signals/issues/4)
**Branch:** `issue-4-add-fitness-plan-with-ai-daily-suggestions`
**Status:** Done
**Created:** 2026-03-28

---

## Problem Summary

There's no way to express fitness goals or intentions in the app. Workouts and health metrics flow in from HealthKit, but there's nothing prescriptive. Users can't say "I want to run 3x/week and do strength 2x/week" and see how reality compares to the plan.

This issue adds:
- A single editable fitness plan (plain English/markdown, database-backed)
- LLM-powered single-shot chat to modify the plan conversationally
- A cached "Today's suggestion" on the dashboard comparing the plan vs last 7 days of actual activity
- Manual re-generation of the daily suggestion

## Key Findings

### Current state
- **Models:** User, HealthMetric, Workout, HealthPayload — no plan or LLM models yet
- **Dashboard:** Server-rendered ERB at `dashboard#index`, mobile-first dark mode with CardComponent and PageLayoutComponent
- **Services:** Follow a clear pattern — service objects in `app/services/`, called from controllers, return Result structs
- **Testing:** Minitest, unit + integration, minimal view tests, no excessive mocking
- **Jobs:** Solid Queue configured but no active jobs — all processing is synchronous
- **Caching:** Solid Cache configured (Postgres-backed) but not actively used yet
- **LLM:** No LLM gems in the codebase — this is the first integration
- **Frontend:** Tailwind v4, ViewComponents, Hotwire (Turbo + Stimulus installed but light usage)

### Architecture decisions (resolved during alignment)
- **Plan content in database text column** (not markdown file on disk). The architecture doc's markdown-vs-Postgres split is about data shape (freeform vs structured), not storage medium. A text column rendered as markdown for the LLM satisfies the principle.
- **ruby_llm gem** (v1.14.0) for LLM integration. Clean API: `RubyLLM.chat(model: "gpt-5-nano").ask("prompt")`. Supports OpenAI, Anthropic, and others. Skip the Rails generators — we don't need persistent chat models.
- **Single-user app** — Plan has `user_id` FK for correctness. Blank plan seeded for the user on deploy.
- **No version history** (explicitly out of scope).

### Data available for daily suggestions
- `Workout` — workout_type, started_at, duration, distance, energy_burned (last 7 days)
- `HealthMetric` — steps, active_energy, sleep_analysis, resting_heart_rate, HRV, weight, body_fat_percentage, VO2max (last 7 days)
- Context formatted as structured markdown for the LLM prompt

## Proposed Approach

### Database

One new table: `plans`
- `id` (pk)
- `user_id` (fk → users, not null, unique index)
- `content` (text) — the plan as plain English/markdown
- `daily_suggestion` (text) — cached suggestion for today
- `suggestion_generated_at` (datetime) — when the suggestion was last generated
- `timestamps`

Single plan per user enforced by unique index on `user_id`. Blank plan seeded for the existing user.

### Services

1. **PlanSuggestionGenerator** — Assembles context (plan content + last 7 days of workouts + last 7 days of key metrics as structured markdown), sends to LLM, returns today's suggestion. Updates `plans.daily_suggestion` and `suggestion_generated_at`. On LLM failure: returns error, keeps stale cached suggestion.

2. **PlanChatService** — Single-shot conversational plan editing. Takes user message + current plan content, sends to LLM, returns updated plan content + response message. Auto-saves the updated plan. On LLM failure: doesn't touch the plan, returns error.

### Routes & Controller

Single controller, singular resource:

```ruby
resource :plan, only: [:show, :edit, :update] do
  post :generate_suggestion
  post :chat
end
```

- `GET /plan` → show plan + daily suggestion + chat input
- `GET /plan/edit` → textarea for manual editing
- `PATCH /plan` → save manual edits
- `POST /plan/generate_suggestion` → regenerate suggestion (redirects back)
- `POST /plan/chat` → send message to LLM, auto-save updated plan (redirects back)

Dashboard integration: `DashboardController#index` loads the plan and shows the suggestion card.

### Views (full page reloads, no Turbo for v1)

- **Dashboard suggestion card** — Top of dashboard, before metrics. Shows cached suggestion + "Regenerate" button. Hidden when plan has no content (shows "Create a fitness plan" prompt instead).
- **Plan show page** — Plan content (rendered markdown) + daily suggestion + single chat input for conversational editing. Response shown as flash or inline after redirect.
- **Plan edit page** — Textarea for direct plan editing.

### LLM Integration

- `ruby_llm` gem added to Gemfile (use basic chat API, not Rails generators)
- Initializer: `RubyLLM.configure { |c| c.openai_api_key = ENV["OPENAI_API_KEY"] }`
- Default model: configurable via `ENV["LLM_MODEL"]`, defaults to `gpt-5-nano`
- System prompts as plain strings in service objects
- No streaming for v1

### Error handling

- LLM failures: flash error, keep existing data unchanged
- No retries or background retry queues

### Testing

- Stub `RubyLLM.chat` in service tests — LLM is an external boundary, appropriate to mock
- Model tests for Plan validations and associations
- Integration tests for controller actions and dashboard rendering
- Follow existing test patterns (Minitest, fixtures)

## Step-by-Step Tasks

### Batch 1: Foundation
- [ ] Add `ruby_llm` gem to Gemfile and create initializer
- [ ] Create `plans` migration and model (validations, unique user index, `belongs_to :user`)
- [ ] Add `has_one :plan` to User model
- [ ] Seed a blank plan for the existing user
- [ ] Write model tests

### Batch 2: Services
- [ ] Create `PlanSuggestionGenerator` service (context assembly + LLM call + cache update)
- [ ] Create `PlanChatService` service (single-shot plan editing via LLM)
- [ ] Write service tests (with LLM stubs)

### Batch 3: Controller & Routes
- [ ] Add routes (`resource :plan` with custom actions)
- [ ] Create `PlansController` (show, edit, update, generate_suggestion, chat)
- [ ] Write integration tests

### Batch 4: Views
- [ ] Build plan show view (plan content + suggestion + chat input)
- [ ] Build plan edit view (textarea form)
- [ ] Add daily suggestion card to dashboard (with empty state)
- [ ] Add nav link to plan page
- [ ] Write smoke tests for views

### Batch 5: Docs
- [ ] Update architecture.md and background.md to reflect LLM integration

## Open Questions / Unknowns

*All resolved during alignment — no blockers.*

- Prompt tuning will be iterative after initial implementation (not a blocker).
- GPT-5 Nano model identifier will be verified at runtime. Model is configurable via env var as fallback.

---

*This plan is a living document — update it as understanding evolves.*
