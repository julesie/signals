# Today Tab Redesign & Workouts History — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the homepage into a Today-centric view with lazy-loaded AI suggestions and plan adherence, and create a dedicated filterable workouts history page.

**Architecture:** Turbo Frames lazy-load two AI-dependent sections (suggestion + adherence) while the rest of the page renders immediately. A new `WorkoutsController` serves the filterable history page. The `PlanAdherenceGenerator` service mirrors the existing `PlanSuggestionGenerator` pattern.

**Tech Stack:** Rails 8, Turbo Frames, ViewComponent, Tailwind CSS v4, RubyLLM, Minitest

**Spec:** `docs/superpowers/specs/2026-03-28-today-tab-and-workouts-history-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `db/migrate/TIMESTAMP_add_adherence_fields_to_plans.rb` | Add `adherence_summary` and `adherence_summary_generated_at` to plans |
| `app/components/loading_spinner_component.rb` | ViewComponent: animated spinner with optional text |
| `app/components/loading_spinner_component.html.erb` | Spinner template |
| `app/services/plan_adherence_generator.rb` | AI service: 7-day + 30-day adherence narrative |
| `app/views/dashboard/suggestion.html.erb` | Turbo Frame response for suggestion |
| `app/views/dashboard/adherence.html.erb` | Turbo Frame response for adherence + bar chart |
| `app/controllers/workouts_controller.rb` | Filterable, paginated workout index |
| `app/views/workouts/index.html.erb` | Workout history page with filters |
| `test/components/loading_spinner_component_test.rb` | Spinner component tests |
| `test/services/plan_adherence_generator_test.rb` | Adherence generator tests |
| `test/integration/workouts_test.rb` | Workouts index integration tests |

### Modified Files

| File | Change |
|------|--------|
| `config/routes.rb` | Add dashboard/suggestion, dashboard/adherence routes + workouts resource |
| `app/controllers/dashboard_controller.rb` | Add `suggestion`, `regenerate_suggestion`, `adherence`, `regenerate_adherence` actions; replace `@recent_workouts` with `@todays_workouts` |
| `app/views/dashboard/index.html.erb` | Replace recent workouts with today's workouts; add Turbo Frames for suggestion + adherence |
| `app/views/layouts/application.html.erb` | Add "Workouts" nav link |
| `app/services/plan_suggestion_generator.rb` | Add today's workouts to AI prompt context |
| `test/integration/dashboard_test.rb` | Update tests for new layout |
| `test/services/plan_suggestion_generator_test.rb` | Test today's workouts in context |
| `test/fixtures/plans.yml` | Add adherence fields to fixtures |

---

## Task 0: Migration — add adherence fields to plans

**Files:**
- Create: `db/migrate/TIMESTAMP_add_adherence_fields_to_plans.rb`
- Modify: `test/fixtures/plans.yml`

- [ ] **Step 1: Generate the migration**

Run:
```bash
bin/rails generate migration AddAdherenceFieldsToPlans adherence_summary:text adherence_summary_generated_at:datetime
```

- [ ] **Step 2: Run the migration**

Run:
```bash
bin/rails db:migrate
```

Expected: Migration succeeds, `db/schema.rb` updated with new columns on `plans` table.

- [ ] **Step 3: Update fixtures**

In `test/fixtures/plans.yml`, add the new fields:

```yaml
with_content:
  user: one
  content: "Run 3x/week, strength training 2x/week, rest on weekends."
  daily_suggestion: "Today is a good day for a 5K easy run."
  suggestion_generated_at: <%= 1.hour.ago.to_fs(:db) %>
  adherence_summary:
  adherence_summary_generated_at:

blank:
  user: two
  content:
  daily_suggestion:
  suggestion_generated_at:
  adherence_summary:
  adherence_summary_generated_at:
```

- [ ] **Step 4: Verify existing tests still pass**

Run:
```bash
bin/rails test
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_add_adherence_fields_to_plans.rb db/schema.rb test/fixtures/plans.yml
git commit -m "feat: add adherence_summary fields to plans table"
```

---

## Task 1: LoadingSpinnerComponent

**Files:**
- Create: `app/components/loading_spinner_component.rb`
- Create: `app/components/loading_spinner_component.html.erb`
- Create: `test/components/loading_spinner_component_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/components/loading_spinner_component_test.rb`:

```ruby
require "test_helper"

class LoadingSpinnerComponentTest < ViewComponent::TestCase
  test "renders spinner with default text" do
    render_inline(LoadingSpinnerComponent.new)

    assert_selector ".animate-spin"
    assert_text "Loading..."
  end

  test "renders spinner with custom text" do
    render_inline(LoadingSpinnerComponent.new(text: "Generating suggestion..."))

    assert_text "Generating suggestion..."
  end

  test "renders without text when nil" do
    render_inline(LoadingSpinnerComponent.new(text: nil))

    assert_selector ".animate-spin"
    assert_no_text "Loading"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/components/loading_spinner_component_test.rb
```

Expected: FAIL — `LoadingSpinnerComponent` not defined.

- [ ] **Step 3: Write the component**

Create `app/components/loading_spinner_component.rb`:

```ruby
# frozen_string_literal: true

class LoadingSpinnerComponent < ViewComponent::Base
  def initialize(text: "Loading...")
    @text = text
  end
end
```

Create `app/components/loading_spinner_component.html.erb`:

```erb
<div class="flex flex-col items-center justify-center py-8">
  <svg class="animate-spin h-8 w-8 text-zinc-400 mb-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
  </svg>
  <% if @text.present? %>
    <p class="text-sm text-zinc-500"><%= @text %></p>
  <% end %>
</div>
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/components/loading_spinner_component_test.rb
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/components/loading_spinner_component.rb app/components/loading_spinner_component.html.erb test/components/loading_spinner_component_test.rb
git commit -m "feat: add LoadingSpinnerComponent for Turbo Frame placeholders"
```

---

## Task 2: Routes + nav link

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, add before the `root` line:

```ruby
  # Dashboard Turbo Frame endpoints
  get "dashboard/suggestion", to: "dashboard#suggestion"
  post "dashboard/suggestion", to: "dashboard#regenerate_suggestion", as: nil
  get "dashboard/adherence", to: "dashboard#adherence"
  post "dashboard/adherence", to: "dashboard#regenerate_adherence", as: nil

  resources :workouts, only: [:index]
```

Note: `as: nil` on the POST routes suppresses duplicate route name generation. The views use `dashboard_suggestion_path` / `dashboard_adherence_path` (from the GET routes) with `method: :post` in `button_to`, which generates a form that POSTs to the same URL.

- [ ] **Step 2: Add Workouts nav link**

In `app/views/layouts/application.html.erb`, inside the `<div class="flex items-center gap-4">` block, add a "Workouts" link before the existing "Plan" link:

```erb
<%= link_to "Workouts", workouts_path, class: "text-sm text-zinc-400 hover:text-zinc-200" %>
```

- [ ] **Step 3: Verify routes exist**

Run:
```bash
bin/rails routes | grep -E "suggestion|adherence|workouts"
```

Expected: Shows all 5 new routes.

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/views/layouts/application.html.erb
git commit -m "feat: add routes for dashboard frames and workouts index"
```

---

## Task 3: Update PlanSuggestionGenerator — workout-aware suggestions

**Files:**
- Modify: `app/services/plan_suggestion_generator.rb`
- Modify: `test/services/plan_suggestion_generator_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/services/plan_suggestion_generator_test.rb`, inserting before the `private` keyword (line 65):

```ruby
test "includes today's completed workouts in the context" do
  Workout.create!(
    external_id: "today-strength",
    workout_type: "Traditional Strength Training",
    started_at: 3.hours.ago,
    ended_at: 2.hours.ago,
    duration: 2400,
    energy_burned: 350
  )

  captured_prompt = nil

  stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
    PlanSuggestionGenerator.call(@plan)
  end

  assert_includes captured_prompt, "Today's Completed Workouts"
  assert_includes captured_prompt, "Traditional Strength Training"
end

test "context says no workouts today when none exist" do
  captured_prompt = nil

  stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
    PlanSuggestionGenerator.call(@plan)
  end

  assert_includes captured_prompt, "No workouts completed yet today"
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
bin/rails test test/services/plan_suggestion_generator_test.rb
```

Expected: 2 new tests FAIL.

- [ ] **Step 3: Update PlanSuggestionGenerator**

In `app/services/plan_suggestion_generator.rb`:

Update `SYSTEM_PROMPT` to mention today's workouts:

```ruby
SYSTEM_PROMPT = <<~PROMPT
  You are a concise fitness coach. Given the user's training plan, their activity over the last 7 days, and any workouts already completed today, tell them what to do for the rest of TODAY. Nothing else — no planning ahead.

  If they've already worked out today, acknowledge it and suggest complementary activity or rest — don't suggest an additional full workout.

  One short paragraph: what to do today and a brief reason why. That's it.
PROMPT
```

Add a `format_todays_workouts` method and replace the `build_context` method entirely. The complete updated private methods section should be:

```ruby
  def build_context
    <<~CONTEXT
      ## Your Plan
      #{@plan.content}

      ## Last 7 Days — Workouts
      #{format_workouts}

      ## Last 7 Days — Health Metrics
      #{format_metrics}

      ## Today's Completed Workouts
      #{format_todays_workouts}

      ## Today
      #{Date.current.strftime("%A, %B %-d, %Y")}
    CONTEXT
  end

  def format_todays_workouts
    workouts = Workout.where(started_at: Date.current.all_day).order(started_at: :asc)
    return "No workouts completed yet today." if workouts.empty?

    workouts.map { |w|
      parts = [w.workout_type]
      parts << "#{(w.duration / 60.0).round} min"
      parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
      "- #{parts.join(", ")}"
    }.join("\n")
  end
```

The `format_workouts` and `format_metrics` methods remain unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
bin/rails test test/services/plan_suggestion_generator_test.rb
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/plan_suggestion_generator.rb test/services/plan_suggestion_generator_test.rb
git commit -m "feat: make suggestion generator aware of today's completed workouts"
```

---

## Task 4: PlanAdherenceGenerator service

**Files:**
- Create: `app/services/plan_adherence_generator.rb`
- Create: `test/services/plan_adherence_generator_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/services/plan_adherence_generator_test.rb`:

```ruby
require "test_helper"

class PlanAdherenceGeneratorTest < ActiveSupport::TestCase
  setup do
    @plan = plans(:with_content)
    @fake_response = Data.define(:content).new(content: "7-day: You ran twice. 30-day: Solid consistency.")
  end

  test "generates adherence summary and caches it on the plan" do
    stub_llm_chat(@fake_response) do
      result = PlanAdherenceGenerator.call(@plan)

      assert result.success
      assert_equal @fake_response.content, result.summary
      assert_equal @fake_response.content, @plan.reload.adherence_summary
      assert_not_nil @plan.adherence_summary_generated_at
    end
  end

  test "returns error on LLM failure without changing the plan" do
    stub_llm_chat_error("API timeout") do
      result = PlanAdherenceGenerator.call(@plan)

      assert_not result.success
      assert_equal "API timeout", result.error
      assert_nil @plan.reload.adherence_summary
    end
  end

  test "includes plan content and workout data in the context" do
    Workout.create!(
      external_id: "adherence-test",
      workout_type: "Running",
      started_at: 2.days.ago,
      ended_at: 2.days.ago + 30.minutes,
      duration: 1800,
      energy_burned: 300
    )

    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanAdherenceGenerator.call(@plan)
    end

    assert_includes captured_prompt, @plan.content
    assert_includes captured_prompt, "Running"
    assert_includes captured_prompt, "Last 7 Days"
    assert_includes captured_prompt, "Last 30 Days"
  end

  private

  def stub_llm_chat(response, capture: nil, &block)
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_params) { |**_| self }
    fake_chat.define_singleton_method(:with_instructions) { |_| self }
    fake_chat.define_singleton_method(:ask) { |prompt|
      capture&.call(prompt)
      response
    }

    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }
    yield
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end

  def stub_llm_chat_error(message, &block)
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| raise message }
    yield
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
bin/rails test test/services/plan_adherence_generator_test.rb
```

Expected: FAIL — `PlanAdherenceGenerator` not defined.

- [ ] **Step 3: Write the service**

Create `app/services/plan_adherence_generator.rb`:

```ruby
class PlanAdherenceGenerator
  Result = Struct.new(:success, :summary, :error, keyword_init: true)

  DEFAULT_MODEL = "gpt-5-nano"

  SYSTEM_PROMPT = <<~PROMPT
    You are a concise fitness coach. Given the user's training plan and their actual activity, provide a brief adherence assessment.

    Write exactly two short paragraphs:
    1. **Last 7 days:** How they tracked against their plan this week.
    2. **Last 30 days:** The broader trend — are they building consistency or drifting?

    Be specific about what they did and didn't do relative to the plan. Encouraging but honest. No fluff.
  PROMPT

  def self.call(plan)
    new(plan).call
  end

  def initialize(plan)
    @plan = plan
  end

  def call
    context = build_context
    response = RubyLLM.chat(model: llm_model)
      .with_params(reasoning_effort: "low")
      .with_instructions(SYSTEM_PROMPT)
      .ask(context)

    @plan.update!(
      adherence_summary: response.content,
      adherence_summary_generated_at: Time.current
    )

    Result.new(success: true, summary: response.content)
  rescue => e
    Rails.logger.error("PlanAdherenceGenerator failed: #{e.class}: #{e.message}")
    Result.new(success: false, error: e.message)
  end

  private

  def llm_model
    ENV.fetch("LLM_MODEL", DEFAULT_MODEL)
  end

  def build_context
    <<~CONTEXT
      ## Your Plan
      #{@plan.content}

      ## Last 7 Days — Workouts
      #{format_workouts(7.days.ago)}

      ## Last 30 Days — Workouts
      #{format_workouts(30.days.ago)}

      ## Last 7 Days — Active Energy
      #{format_active_energy}

      ## Today
      #{Date.current.strftime("%A, %B %-d, %Y")}
    CONTEXT
  end

  def format_workouts(since)
    workouts = Workout.where(started_at: since..).order(started_at: :asc)
    return "No workouts recorded." if workouts.empty?

    workouts.map { |w|
      parts = [w.started_at.strftime("%a %b %-d")]
      parts << w.workout_type
      parts << "#{(w.duration / 60.0).round} min"
      parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
      "- #{parts.join(", ")}"
    }.join("\n")
  end

  def format_active_energy
    metrics = HealthMetric.where(metric_name: "active_energy", recorded_at: 7.days.ago..)
    return "No active energy data." if metrics.empty?

    daily = metrics.group_by { |m| m.recorded_at.to_date }.transform_values { |ms| ms.sum(&:value) }
    daily.sort.map { |date, total| "- #{date.strftime("%a %b %-d")}: #{total.round} kcal" }.join("\n")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
bin/rails test test/services/plan_adherence_generator_test.rb
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/plan_adherence_generator.rb test/services/plan_adherence_generator_test.rb
git commit -m "feat: add PlanAdherenceGenerator for 7/30-day adherence narratives"
```

---

## Task 5: Dashboard controller — new actions + today's workouts

**Files:**
- Modify: `app/controllers/dashboard_controller.rb`
- Create: `app/views/dashboard/suggestion.html.erb`
- Create: `app/views/dashboard/adherence.html.erb`

- [ ] **Step 1: Update the dashboard controller**

Replace `app/controllers/dashboard_controller.rb` with:

```ruby
class DashboardController < ApplicationController
  METRIC_TYPES = %w[weight body_fat_percentage vo2_max resting_heart_rate heart_rate_variability step_count active_energy dietary_energy].freeze
  ACTIVE_CALORIES_GOAL = 500

  def index
    @plan = current_user.plan
    @todays_workouts = Workout.where(started_at: Date.current.all_day).order(started_at: :desc)
    @latest_metrics = METRIC_TYPES.filter_map do |name|
      HealthMetric.where(metric_name: name).order(recorded_at: :desc).first
    end
    @latest_sleep = HealthMetric.where(metric_name: "sleep_analysis").order(recorded_at: :desc).first
    @pipeline_stats = {
      total_payloads: HealthPayload.count,
      last_received: HealthPayload.order(created_at: :desc).first&.created_at,
      failed_count: HealthPayload.where(status: "failed").count
    }
  end

  def suggestion
    @plan = current_user.plan
    generate_suggestion_if_needed
    render layout: false
  end

  def regenerate_suggestion
    @plan = current_user.plan || current_user.create_plan
    @result = PlanSuggestionGenerator.call(@plan)
    @plan.reload
    render :suggestion, layout: false
  end

  def adherence
    @plan = current_user.plan
    generate_adherence_if_needed
    load_active_calories
    render layout: false
  end

  def regenerate_adherence
    @plan = current_user.plan || current_user.create_plan
    @result = PlanAdherenceGenerator.call(@plan)
    @plan.reload
    load_active_calories
    render :adherence, layout: false
  end

  private

  def generate_suggestion_if_needed
    return unless @plan&.has_content?
    return if @plan.suggestion_generated_at&.to_date == Date.current

    @result = PlanSuggestionGenerator.call(@plan)
    @plan.reload
  end

  def generate_adherence_if_needed
    return unless @plan&.has_content?
    return if @plan.adherence_summary_generated_at&.to_date == Date.current

    @result = PlanAdherenceGenerator.call(@plan)
    @plan.reload
  end

  def load_active_calories
    metrics = HealthMetric.where(metric_name: "active_energy", recorded_at: 7.days.ago..)
    daily = metrics.group_by { |m| m.recorded_at.to_date }.transform_values { |ms| ms.sum(&:value).round }

    @active_calories_days = (6.days.ago.to_date..Date.current).map do |date|
      { date: date, calories: daily[date] || 0 }
    end

    @calories_max = [@active_calories_days.map { |d| d[:calories] }.max || 0, ACTIVE_CALORIES_GOAL].max
  end
end
```

- [ ] **Step 2: Create suggestion Turbo Frame template**

Create `app/views/dashboard/suggestion.html.erb`:

```erb
<turbo-frame id="suggestion">
  <% if @plan&.has_content? %>
    <% if @result && !@result.success %>
      <%= render(CardComponent.new) do %>
        <div class="text-center py-4">
          <p class="text-red-400 mb-3">Could not generate suggestion. Try again later.</p>
          <%= button_to "Retry", dashboard_suggestion_path, method: :post, class: "text-sm text-blue-400 hover:text-blue-300" %>
        </div>
      <% end %>
    <% elsif @plan.has_suggestion? %>
      <%= render(CardComponent.new) do %>
        <div class="flex items-center justify-between mb-2">
          <h2 class="text-lg font-semibold">Today's Suggestion</h2>
          <div class="flex items-center gap-3">
            <%= link_to "View plan", plan_path, class: "text-sm text-zinc-400 hover:text-zinc-200" %>
            <%= button_to "Regenerate", dashboard_suggestion_path, method: :post, class: "text-sm text-zinc-400 hover:text-zinc-200" %>
          </div>
        </div>
        <div class="text-zinc-300 text-sm">
          <%= simple_format(@plan.daily_suggestion) %>
        </div>
        <% if @plan.suggestion_generated_at %>
          <p class="mt-3 text-xs text-zinc-500">Generated <%= time_ago_in_words(@plan.suggestion_generated_at) %> ago</p>
        <% end %>
      <% end %>
    <% else %>
      <%= render(CardComponent.new) do %>
        <div class="text-center py-4">
          <p class="text-zinc-500 mb-3">No suggestion yet.</p>
          <%= button_to "Generate suggestion", dashboard_suggestion_path, method: :post, class: "text-sm text-blue-400 hover:text-blue-300" %>
        </div>
      <% end %>
    <% end %>
  <% elsif @plan && !@plan.has_content? %>
    <%= render(CardComponent.new) do %>
      <div class="text-center py-4">
        <p class="text-zinc-500 mb-2">No fitness plan yet.</p>
        <%= link_to "Create a plan", edit_plan_path, class: "text-sm text-blue-400 hover:text-blue-300" %>
        <span class="text-zinc-600 text-sm"> to get daily activity suggestions</span>
      </div>
    <% end %>
  <% end %>
</turbo-frame>
```

- [ ] **Step 3: Create adherence Turbo Frame template**

Create `app/views/dashboard/adherence.html.erb`:

```erb
<turbo-frame id="adherence">
  <% if @plan&.has_content? %>
    <% if @result && !@result.success %>
      <%= render(CardComponent.new) do %>
        <div class="text-center py-4">
          <p class="text-red-400 mb-3">Could not generate adherence summary. Try again later.</p>
          <%= button_to "Retry", dashboard_adherence_path, method: :post, class: "text-sm text-blue-400 hover:text-blue-300" %>
        </div>
      <% end %>
    <% else %>
      <%# AI Narrative %>
      <% if @plan.adherence_summary.present? %>
        <%= render(CardComponent.new) do %>
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-lg font-semibold">Plan Adherence</h2>
            <%= button_to "Regenerate", dashboard_adherence_path, method: :post, class: "text-sm text-zinc-400 hover:text-zinc-200" %>
          </div>
          <div class="text-zinc-300 text-sm">
            <%= simple_format(@plan.adherence_summary) %>
          </div>
          <% if @plan.adherence_summary_generated_at %>
            <p class="mt-3 text-xs text-zinc-500">Generated <%= time_ago_in_words(@plan.adherence_summary_generated_at) %> ago</p>
          <% end %>
        <% end %>
      <% end %>

      <%# Active Calories Bar Chart %>
      <% if @active_calories_days.present? %>
        <%= render(CardComponent.new) do %>
          <h3 class="text-sm font-medium text-zinc-400 mb-4">Active Calories — Last 7 Days</h3>
          <div class="relative h-40">
            <%# Goal line %>
            <% goal_pct = (DashboardController::ACTIVE_CALORIES_GOAL.to_f / @calories_max * 100).round %>
            <div class="absolute w-full border-t border-dashed border-green-500/50" style="bottom: <%= goal_pct %>%">
              <span class="absolute -top-4 right-0 text-xs text-green-500/70"><%= DashboardController::ACTIVE_CALORIES_GOAL %> kcal</span>
            </div>

            <%# Bars %>
            <div class="flex items-end justify-between h-full gap-2">
              <% @active_calories_days.each do |day| %>
                <% bar_pct = @calories_max > 0 ? (day[:calories].to_f / @calories_max * 100).round : 0 %>
                <div class="flex-1 flex flex-col items-center">
                  <div class="w-full rounded-t <%= day[:calories] >= DashboardController::ACTIVE_CALORIES_GOAL ? 'bg-green-500' : 'bg-blue-500' %>"
                       style="height: <%= bar_pct %>%"
                       title="<%= day[:calories] %> kcal">
                  </div>
                  <span class="text-xs text-zinc-500 mt-1"><%= day[:date].strftime("%a") %></span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
</turbo-frame>
```

- [ ] **Step 4: Verify the app boots without errors**

Run:
```bash
bin/rails test test/integration/dashboard_test.rb
```

Expected: Existing tests may need updating (handled in Task 6). At minimum, the app should boot and controller actions should be defined.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/dashboard_controller.rb app/views/dashboard/suggestion.html.erb app/views/dashboard/adherence.html.erb
git commit -m "feat: add dashboard suggestion/adherence actions with Turbo Frame templates"
```

---

## Task 6: Redesign dashboard index view

**Files:**
- Modify: `app/views/dashboard/index.html.erb`
- Modify: `test/integration/dashboard_test.rb`

- [ ] **Step 1: Rewrite the dashboard view**

Replace `app/views/dashboard/index.html.erb` with the new layout. The key changes are:

1. Replace the inline suggestion section with a lazy-loaded Turbo Frame
2. Add Today's Workouts section (server-rendered)
3. Add lazy-loaded Turbo Frame for adherence
4. Keep metrics, sleep, and pipeline status unchanged
5. Move sync status to the bottom with pipeline status

```erb
<%= render(PageLayoutComponent.new) do %>
  <div class="space-y-8">
    <%# Today's Suggestion (Turbo Frame — lazy-loaded) %>
    <section>
      <turbo-frame id="suggestion" src="<%= dashboard_suggestion_path %>" loading="lazy">
        <%= render(LoadingSpinnerComponent.new(text: "Generating suggestion...")) %>
      </turbo-frame>
    </section>

    <%# Today's Workouts %>
    <section>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Today's Workouts</h2>
        <%= link_to "View all", workouts_path, class: "text-sm text-zinc-400 hover:text-zinc-200" %>
      </div>
      <% if @todays_workouts.any? %>
        <div class="space-y-3">
          <% @todays_workouts.each do |workout| %>
            <%= render(CardComponent.new) do %>
              <div class="flex items-center justify-between mb-2">
                <span class="font-medium"><%= workout.workout_type %></span>
                <span class="text-xs text-zinc-500"><%= workout.started_at.strftime("%-I:%M %p") %></span>
              </div>
              <div class="flex flex-wrap gap-x-4 gap-y-1 text-sm text-zinc-400">
                <span>
                  <% hours = workout.duration.to_i / 3600 %>
                  <% minutes = (workout.duration.to_i % 3600) / 60 %>
                  <%= hours > 0 ? "#{hours}h #{minutes}m" : "#{minutes}m" %>
                </span>
                <% if workout.distance.present? && workout.distance > 0 %>
                  <span><%= number_with_precision(workout.distance, precision: 1, strip_insignificant_zeros: true) %> <%= workout.distance_units %></span>
                <% end %>
                <% if workout.energy_burned.present? && workout.energy_burned > 0 %>
                  <span><%= workout.energy_burned.to_i %> kcal</span>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <%= render(CardComponent.new) do %>
          <p class="text-center text-zinc-500">No workouts recorded today.</p>
        <% end %>
      <% end %>
    </section>

    <%# Plan Adherence (Turbo Frame — lazy-loaded) %>
    <section>
      <turbo-frame id="adherence" src="<%= dashboard_adherence_path %>" loading="lazy">
        <%= render(LoadingSpinnerComponent.new(text: "Analyzing plan adherence...")) %>
      </turbo-frame>
    </section>

    <%# Latest Metrics %>
    <section>
      <h2 class="text-lg font-semibold mb-4">Latest Metrics</h2>
      <% if @latest_metrics.any? %>
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          <% @latest_metrics.each do |metric| %>
            <%= render(CardComponent.new) do %>
              <p class="text-sm text-zinc-400"><%= metric.metric_name.titleize %></p>
              <p class="mt-1 text-2xl font-bold">
                <%= number_with_precision(metric.value, precision: 1, strip_insignificant_zeros: true) %>
                <span class="text-sm font-normal text-zinc-400"><%= metric.units %></span>
              </p>
              <p class="mt-1 text-xs text-zinc-500"><%= time_ago_in_words(metric.recorded_at) %> ago</p>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <%= render(CardComponent.new) do %>
          <p class="text-center text-zinc-500">No metrics yet</p>
        <% end %>
      <% end %>
    </section>

    <%# Sleep %>
    <section>
      <h2 class="text-lg font-semibold mb-4">Sleep</h2>
      <% if @latest_sleep %>
        <%= render(CardComponent.new) do %>
          <div class="flex items-baseline gap-2 mb-4">
            <span class="text-3xl font-bold"><%= number_with_precision(@latest_sleep.value, precision: 1) %></span>
            <span class="text-sm text-zinc-400">hours of sleep</span>
          </div>

          <% meta = @latest_sleep.metadata || {} %>
          <% if meta["sleepStart"].present? || meta["sleepEnd"].present? %>
            <div class="flex gap-6 text-sm text-zinc-300 mb-4">
              <% if meta["sleepStart"].present? %>
                <div>
                  <span class="text-zinc-500">Asleep:</span>
                  <%= Time.parse(meta["sleepStart"]).strftime("%-I:%M %p") %>
                </div>
              <% end %>
              <% if meta["sleepEnd"].present? %>
                <div>
                  <span class="text-zinc-500">Awake:</span>
                  <%= Time.parse(meta["sleepEnd"]).strftime("%-I:%M %p") %>
                </div>
              <% end %>
              <% if meta["inBed"].present? %>
                <div>
                  <span class="text-zinc-500">In bed:</span>
                  <%= number_with_precision(meta["inBed"], precision: 1) %> hr
                </div>
              <% end %>
            </div>
          <% end %>

          <% if meta["core"].present? && meta["deep"].present? && meta["rem"].present? && @latest_sleep.value > 0 %>
            <% total = @latest_sleep.value.to_f %>
            <% core_pct = (meta["core"].to_f / total * 100).round %>
            <% deep_pct = (meta["deep"].to_f / total * 100).round %>
            <% rem_pct = (meta["rem"].to_f / total * 100).round %>
            <div class="mb-2">
              <div class="flex h-4 rounded-full overflow-hidden">
                <div class="bg-blue-400" style="width: <%= core_pct %>%"></div>
                <div class="bg-indigo-500" style="width: <%= deep_pct %>%"></div>
                <div class="bg-purple-400" style="width: <%= rem_pct %>%"></div>
              </div>
            </div>
            <div class="flex gap-4 text-xs text-zinc-400">
              <div class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 rounded bg-blue-400"></span>
                Core <%= number_with_precision(meta["core"], precision: 1) %> hr
              </div>
              <div class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 rounded bg-indigo-500"></span>
                Deep <%= number_with_precision(meta["deep"], precision: 1) %> hr
              </div>
              <div class="flex items-center gap-1">
                <span class="inline-block w-3 h-3 rounded bg-purple-400"></span>
                REM <%= number_with_precision(meta["rem"], precision: 1) %> hr
              </div>
            </div>
          <% end %>
        <% end %>
      <% else %>
        <%= render(CardComponent.new) do %>
          <p class="text-center text-zinc-500">No sleep data yet</p>
        <% end %>
      <% end %>
    </section>

    <%# Sync / Pipeline Status %>
    <section>
      <div class="flex items-center gap-4 text-sm text-zinc-500 bg-zinc-800/50 rounded-lg px-4 py-3">
        <% if @pipeline_stats[:last_received] %>
          <span>Last sync: <%= time_ago_in_words(@pipeline_stats[:last_received]) %> ago</span>
        <% else %>
          <span>No data synced yet</span>
        <% end %>
        <span><%= @pipeline_stats[:total_payloads] %> payload<%= @pipeline_stats[:total_payloads] == 1 ? "" : "s" %> processed</span>
        <% if @pipeline_stats[:failed_count] > 0 %>
          <span class="text-red-400 font-medium"><%= @pipeline_stats[:failed_count] %> failed</span>
        <% end %>
      </div>
    </section>
  </div>
<% end %>
```

- [ ] **Step 2: Update dashboard integration tests**

Replace `test/integration/dashboard_test.rb`:

```ruby
require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user

    HealthMetric.create!(metric_name: "weight", recorded_at: 1.hour.ago, value: 82.5, units: "kg")
    HealthMetric.create!(metric_name: "resting_heart_rate", recorded_at: 1.hour.ago, value: 58, units: "bpm")
    HealthMetric.create!(
      metric_name: "sleep_analysis", recorded_at: 1.hour.ago, value: 7.2, units: "hr",
      metadata: {"core" => 3.5, "deep" => 1.8, "rem" => 1.5,
                 "sleepStart" => "2026-03-13 22:45:00", "sleepEnd" => "2026-03-14 06:05:00",
                 "inBed" => 7.5}
    )
    HealthPayload.create!(raw_json: {data: {}}, status: "processed")
  end

  test "dashboard shows metric values" do
    get root_path
    assert_response :success
    assert_match "82.5", response.body
    assert_match "58", response.body
  end

  test "dashboard shows sleep data" do
    get root_path
    assert_match "7.2", response.body
  end

  test "dashboard shows today's workouts" do
    Workout.create!(
      external_id: "today-run", workout_type: "Running",
      started_at: 2.hours.ago, ended_at: 1.hour.ago, duration: 3600,
      distance: 10.0, distance_units: "km", energy_burned: 600
    )
    get root_path
    assert_match "Running", response.body
    assert_match "Today's Workouts", response.body
  end

  test "dashboard shows empty state when no workouts today" do
    get root_path
    assert_match "No workouts recorded today", response.body
  end

  test "dashboard shows pipeline status" do
    get root_path
    assert_match "processed", response.body.downcase
  end

  test "dashboard has turbo frames for suggestion and adherence" do
    get root_path
    assert_match 'turbo-frame id="suggestion"', response.body
    assert_match 'turbo-frame id="adherence"', response.body
  end

  test "dashboard has link to workouts page" do
    get root_path
    assert_match "View all", response.body
  end

  test "dashboard renders without data" do
    HealthMetric.delete_all
    Workout.delete_all
    HealthPayload.delete_all
    get root_path
    assert_response :success
  end
end
```

- [ ] **Step 3: Run tests**

Run:
```bash
bin/rails test test/integration/dashboard_test.rb
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add app/views/dashboard/index.html.erb test/integration/dashboard_test.rb
git commit -m "feat: redesign dashboard with Today's Workouts and Turbo Frame sections"
```

---

## Task 7: Workouts index page

**Files:**
- Create: `app/controllers/workouts_controller.rb`
- Create: `app/views/workouts/index.html.erb`
- Create: `test/integration/workouts_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/integration/workouts_test.rb`:

```ruby
require "test_helper"

class WorkoutsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user

    @run = Workout.create!(
      external_id: "w-run", workout_type: "Outdoor Run",
      started_at: 2.days.ago, ended_at: 2.days.ago + 30.minutes,
      duration: 1800, distance: 5.0, distance_units: "km", energy_burned: 300,
      metadata: {"heartRate" => {"avg" => 155}}
    )
    @swim = Workout.create!(
      external_id: "w-swim", workout_type: "Pool Swim",
      started_at: 1.day.ago, ended_at: 1.day.ago + 40.minutes,
      duration: 2400, energy_burned: 400
    )
  end

  test "workouts index shows all workouts" do
    get workouts_path
    assert_response :success
    assert_match "Outdoor Run", response.body
    assert_match "Pool Swim", response.body
  end

  test "workouts index filters by workout type" do
    get workouts_path, params: {workout_type: "Outdoor Run"}
    assert_response :success
    assert_match "Outdoor Run", response.body
    assert_no_match "Pool Swim", response.body
  end

  test "workouts index filters by date range" do
    get workouts_path, params: {from: 3.days.ago.to_date.to_s, to: 1.day.ago.to_date.to_s}
    assert_response :success
    assert_match "Outdoor Run", response.body
  end

  test "workouts index shows empty state" do
    Workout.delete_all
    get workouts_path
    assert_response :success
    assert_match "No workouts found", response.body
  end

  test "workouts index requires authentication" do
    sign_out @user
    get workouts_path
    assert_response :redirect
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
bin/rails test test/integration/workouts_test.rb
```

Expected: FAIL — `WorkoutsController` not defined.

- [ ] **Step 3: Write the controller**

Create `app/controllers/workouts_controller.rb`:

```ruby
class WorkoutsController < ApplicationController
  PER_PAGE = 20

  def index
    @workout_types = Workout.distinct.pluck(:workout_type).sort

    workouts = Workout.order(started_at: :desc)
    workouts = workouts.where(workout_type: params[:workout_type]) if params[:workout_type].present?

    if params[:from].present? || params[:to].present?
      from_date = params[:from].present? ? Date.parse(params[:from]).beginning_of_day : nil
      to_date = params[:to].present? ? Date.parse(params[:to]).end_of_day : nil
      workouts = workouts.where(started_at: (from_date || Time.at(0))..(to_date || Time.current))
    else
      workouts = workouts.where(started_at: 30.days.ago..)
    end

    @page = (params[:page] || 1).to_i
    @total_count = workouts.count
    @workouts = workouts.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
  end
end
```

- [ ] **Step 4: Write the view**

Create `app/views/workouts/index.html.erb`:

```erb
<%= render(PageLayoutComponent.new) do %>
  <div class="space-y-6">
    <h1 class="text-xl font-semibold">Workouts</h1>

    <%# Filters %>
    <%= render(CardComponent.new) do %>
      <%= form_tag workouts_path, method: :get, class: "flex flex-wrap items-end gap-4" do %>
        <div class="flex-1 min-w-[140px]">
          <label class="block text-xs text-zinc-400 mb-1">Type</label>
          <%= select_tag :workout_type,
            options_for_select([["All types", ""]] + @workout_types.map { |t| [t, t] }, params[:workout_type]),
            class: "w-full bg-zinc-700 text-zinc-200 text-sm rounded px-3 py-2 border border-zinc-600" %>
        </div>
        <div>
          <label class="block text-xs text-zinc-400 mb-1">From</label>
          <%= date_field_tag :from, params[:from],
            class: "bg-zinc-700 text-zinc-200 text-sm rounded px-3 py-2 border border-zinc-600" %>
        </div>
        <div>
          <label class="block text-xs text-zinc-400 mb-1">To</label>
          <%= date_field_tag :to, params[:to],
            class: "bg-zinc-700 text-zinc-200 text-sm rounded px-3 py-2 border border-zinc-600" %>
        </div>
        <div>
          <%= submit_tag "Filter", class: "bg-blue-600 hover:bg-blue-500 text-white text-sm rounded px-4 py-2 cursor-pointer" %>
        </div>
        <% if params[:workout_type].present? || params[:from].present? || params[:to].present? %>
          <div>
            <%= link_to "Clear", workouts_path, class: "text-sm text-zinc-400 hover:text-zinc-200" %>
          </div>
        <% end %>
      <% end %>
    <% end %>

    <%# Results %>
    <% if @workouts.any? %>
      <p class="text-sm text-zinc-500"><%= @total_count %> workout<%= @total_count == 1 ? "" : "s" %></p>

      <%# Mobile: stacked cards %>
      <div class="md:hidden space-y-3">
        <% @workouts.each do |workout| %>
          <%= render(CardComponent.new) do %>
            <div class="flex items-center justify-between mb-2">
              <span class="font-medium"><%= workout.workout_type %></span>
              <span class="text-xs text-zinc-500"><%= workout.started_at.strftime("%b %-d") %></span>
            </div>
            <div class="flex flex-wrap gap-x-4 gap-y-1 text-sm text-zinc-400">
              <span>
                <% hours = workout.duration.to_i / 3600 %>
                <% minutes = (workout.duration.to_i % 3600) / 60 %>
                <%= hours > 0 ? "#{hours}h #{minutes}m" : "#{minutes}m" %>
              </span>
              <% if workout.distance.present? && workout.distance > 0 %>
                <span><%= number_with_precision(workout.distance, precision: 1, strip_insignificant_zeros: true) %> <%= workout.distance_units %></span>
              <% end %>
              <% avg_hr = workout.metadata&.dig("heartRate", "avg") %>
              <% if avg_hr.present? %>
                <span><%= avg_hr.to_i %> bpm</span>
              <% end %>
              <% if workout.energy_burned.present? && workout.energy_burned > 0 %>
                <span><%= workout.energy_burned.to_i %> kcal</span>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>

      <%# Desktop: table %>
      <div class="hidden md:block">
        <%= render(CardComponent.new(flush: true)) do %>
          <table class="min-w-full divide-y divide-zinc-700">
            <thead class="bg-zinc-700/50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase">Type</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase">Date</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase">Duration</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase">Distance</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase">Avg HR</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase">Energy</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <% @workouts.each do |workout| %>
                <tr>
                  <td class="px-6 py-4 text-sm font-medium"><%= workout.workout_type %></td>
                  <td class="px-6 py-4 text-sm text-zinc-400"><%= workout.started_at.strftime("%b %-d, %Y %-I:%M %p") %></td>
                  <td class="px-6 py-4 text-sm text-zinc-400">
                    <% hours = workout.duration.to_i / 3600 %>
                    <% minutes = (workout.duration.to_i % 3600) / 60 %>
                    <%= hours > 0 ? "#{hours}h #{minutes}m" : "#{minutes}m" %>
                  </td>
                  <td class="px-6 py-4 text-sm text-zinc-400">
                    <% if workout.distance.present? && workout.distance > 0 %>
                      <%= number_with_precision(workout.distance, precision: 1, strip_insignificant_zeros: true) %> <%= workout.distance_units %>
                    <% else %>
                      &mdash;
                    <% end %>
                  </td>
                  <td class="px-6 py-4 text-sm text-zinc-400">
                    <% avg_hr = workout.metadata&.dig("heartRate", "avg") %>
                    <% if avg_hr.present? %>
                      <%= avg_hr.to_i %> bpm
                    <% else %>
                      &mdash;
                    <% end %>
                  </td>
                  <td class="px-6 py-4 text-sm text-zinc-400">
                    <% if workout.energy_burned.present? && workout.energy_burned > 0 %>
                      <%= workout.energy_burned.to_i %> kcal
                    <% else %>
                      &mdash;
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>

      <%# Pagination %>
      <% if @total_pages > 1 %>
        <div class="flex justify-center gap-2">
          <% if @page > 1 %>
            <%= link_to "Previous", workouts_path(page: @page - 1, workout_type: params[:workout_type], from: params[:from], to: params[:to]),
              class: "text-sm text-zinc-400 hover:text-zinc-200 px-3 py-1 bg-zinc-800 rounded" %>
          <% end %>
          <span class="text-sm text-zinc-500 px-3 py-1">Page <%= @page %> of <%= @total_pages %></span>
          <% if @page < @total_pages %>
            <%= link_to "Next", workouts_path(page: @page + 1, workout_type: params[:workout_type], from: params[:from], to: params[:to]),
              class: "text-sm text-zinc-400 hover:text-zinc-200 px-3 py-1 bg-zinc-800 rounded" %>
          <% end %>
        </div>
      <% end %>
    <% else %>
      <%= render(CardComponent.new) do %>
        <p class="text-center text-zinc-500">No workouts found</p>
      <% end %>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```bash
bin/rails test test/integration/workouts_test.rb
```

Expected: All 5 tests PASS.

- [ ] **Step 6: Run full test suite**

Run:
```bash
bin/rails test
```

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/workouts_controller.rb app/views/workouts/index.html.erb test/integration/workouts_test.rb
git commit -m "feat: add filterable, paginated workouts history page"
```

---

## Task 8: Turbo Frame integration tests

**Files:**
- Modify: `test/integration/dashboard_test.rb`

- [ ] **Step 1: Add Turbo Frame endpoint tests**

Append to `test/integration/dashboard_test.rb`:

```ruby
test "suggestion endpoint returns turbo frame" do
  # Stub the LLM to avoid real API calls
  get dashboard_suggestion_path
  assert_response :success
  assert_match "turbo-frame", response.body
end

test "adherence endpoint returns turbo frame" do
  get dashboard_adherence_path
  assert_response :success
  assert_match "turbo-frame", response.body
end

test "regenerate suggestion via POST returns turbo frame" do
  post dashboard_suggestion_path
  assert_response :success
  assert_match "turbo-frame", response.body
end

test "regenerate adherence via POST returns turbo frame" do
  post dashboard_adherence_path
  assert_response :success
  assert_match "turbo-frame", response.body
end
```

Note: Without LLM stubbing, these tests exercise the error/cached path only (no API key in test). The tests verify the endpoints return Turbo Frame HTML regardless of AI success/failure. This is acceptable for integration tests — the AI service logic is unit-tested separately in `PlanSuggestionGeneratorTest` and `PlanAdherenceGeneratorTest`.

- [ ] **Step 2: Run the tests**

Run:
```bash
bin/rails test test/integration/dashboard_test.rb
```

Expected: All tests PASS.

- [ ] **Step 3: Run full suite**

Run:
```bash
bin/rails test
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add test/integration/dashboard_test.rb
git commit -m "test: add integration tests for Turbo Frame suggestion and adherence endpoints"
```

---

## Task 9: Manual smoke test

- [ ] **Step 1: Start the dev server**

Run:
```bash
bin/dev
```

- [ ] **Step 2: Visit the homepage**

Open `http://localhost:3000` in a browser. Verify:
- Spinners appear briefly for suggestion and adherence sections
- Today's Workouts section renders (likely empty in dev)
- Metrics, sleep, and pipeline status display correctly
- Suggestion and adherence Turbo Frames load asynchronously
- "View all" links to `/workouts`
- "Workouts" appears in nav bar

- [ ] **Step 3: Visit the workouts page**

Open `http://localhost:3000/workouts`. Verify:
- Filter form displays with type dropdown, date inputs
- Workouts display in table (desktop) or cards (mobile)
- Pagination works if >20 workouts
- Filtering by type and date range works

- [ ] **Step 4: Test regenerate buttons**

Click "Regenerate" on suggestion and adherence sections. Verify:
- Content updates within the Turbo Frame (no full page reload)
- New timestamp shows

- [ ] **Step 5: Commit any fixes found during smoke testing**
