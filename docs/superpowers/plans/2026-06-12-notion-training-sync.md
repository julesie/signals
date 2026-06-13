# Notion Training Sync Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically keep three Notion databases (Daily Logs, Workouts, Weekly Reviews) up to date from Apple Health data in the Signals Postgres DB, including LLM commentary, with no manual Claude iOS step.

**Architecture:** Webhook-chained `NotionSyncJob` (Solid Queue) syncs data fields to Notion via a minimal `Notion::Client` REST wrapper; a 30-min recurring catch-up self-heals; evening `ruby_llm` jobs write workout commentary, daily narrative + red flags, and the Sunday weekly review. Strict field ownership (automation vs human) makes every write idempotent and safe.

**Tech Stack:** Rails 8.1, Solid Queue (in Puma), `ruby_llm`, `Net::HTTP` (no new gems), Notion REST API version `2025-09-03` (data-source endpoints), Minitest.

**Spec:** `docs/superpowers/specs/2026-06-12-notion-training-sync-design.md` — read it first; the field-ownership tables there are authoritative.

---

## Key facts the spec assumes (verified against codebase)

- Health data arrives at `Api::V1::HealthDataController#create` → `HealthDataProcessor` → `health_metrics` / `workouts` tables. User is hardcoded: `User.find_by!(email: "jules@julescoleman.com")`.
- Canonical `health_metrics.metric_name` values (see `MetricsParser`): `weight` (kg), `sleep_analysis` (value = total sleep hours), `heart_rate_variability` (ms), `resting_heart_rate` (bpm), `active_energy` (kcal), `basal_energy_burned` (kcal), `steps`.
- `workouts` columns: `external_id`, `workout_type` (Apple names like `"Running"`, `"Traditional Strength Training"`, `"Golf"`), `started_at`/`ended_at` (UTC), `duration` (seconds), `distance` + `distance_units`, `energy_burned` (kcal), `metadata` (jsonb; `metadata["heartRate"]["avg"]` when present — see `WorkoutParser#build_metadata`).
- LLM pattern to copy: `PlanSuggestionGenerator` (`RubyLLM.chat(model: ENV.fetch("LLM_MODEL", "gpt-5-nano")).with_params(reasoning_effort: "medium").with_instructions(...).ask(context)`), and its test's `stub_llm_chat` helper.
- Runna plan text lives in `plans.content` (single `Plan` per user).
- Tests: Minitest + fixtures (`users(:one)`, `plans(:with_content)`). No WebMock — stub objects/singleton methods, as existing tests do.
- `config/recurring.yml` has a `production:` section; Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA=true` on Render).

## Environment variables

Add to local `.env` (NOTION_API_TOKEN is already there) and Render dashboard:

```bash
NOTION_API_TOKEN=ntn_...                                        # already set
NOTION_DAILY_LOGS_DS_ID=78d04a40-94e2-49e7-9199-7647f9f185bb
NOTION_WORKOUTS_DS_ID=ffb81591-e4b5-4204-bd12-45d939757458
NOTION_WEEKLY_REVIEWS_DS_ID=a36524f3-9afd-4cf9-8be1-d0bf0b2c21fb
TRAINING_WEEK1_START=2026-05-04   # Monday of W1. Derived from "Thu Jun 11 (W6 D4)" — Jules to confirm.
```

`.env` is NOT auto-loaded by Rails (no dotenv gem). For local `rails runner` smoke tests, prefix commands as shown in Task 3 Step 6.

## Notion property-type cheat sheet (from live schemas)

- **Daily Logs**: title `Day`; date `Date`; numbers `Weight (kg)`, `Sleep Hours`, `Sleep Score`, `HRV`, `RHR`, `Calories Actual`, `Calories Burned`, `Calories Target`, `Deficit`, `Protein (g)`, `Fat (g)`, `Carbs (g)`, `Alcohol (drinks)`; selects `Day Type`, `Mood`, `Withdrawal Bleed`; multi-select `Red Flags`; rich_text `Notes`.
- **Workouts**: title `Session`; date `Date`; numbers `Actual Distance (km)`, `Actual Duration (min)`, `Actual Avg HR`, `kCal Burned`, `Planned Distance (km)`, `RPE`, `Week`; rich_text `Actual Avg Pace`, `Planned Description`, `Notes`; selects `Type` (Easy/Quality/Long/Race/Strength/Mobility/Golf/Cross/Rest), `Status` (Planned/Done/Skipped/Modified), `Felt`; checkboxes `Fueled Properly`, `Hit Prescribed Pace`.
- **Weekly Reviews**: title `Week`; date `Week Start`; numbers `Week Number`, `Planned km`, `Actual km`, `Long Run Distance (km)`, `Avg HRV`, `Avg RHR`, `Avg Sleep Hours`, `Weight Start (kg)`, `Weight End (kg)`; checkboxes `Quality Session Done`, `Strength Done`; select `Status` (On Track/Cautious/Concern/Off Plan); multi-select `Red Flags Triggered` (note: option is `Sleep short`, not `Sleep <6.5h`); rich_text `What Worked`, `What Broke`, `Adjustment for Next Week`.

## File structure

| File | Responsibility |
|---|---|
| `db/migrate/..._add_notion_page_id_to_workouts.rb` | Link DB workouts to Notion pages |
| `app/services/notion/properties.rb` | Build/read Notion property JSON (pure functions) |
| `app/services/notion/client.rb` | HTTP wrapper: `query_data_source`, `create_page`, `update_page`, `append_blocks` |
| `app/services/notion/training_week.rb` | Week/day numbering + PT date helpers |
| `app/services/notion/daily_log_sync.rb` | Upsert one Daily Logs row's data fields |
| `app/services/notion/workout_sync.rb` | Match-and-fill Workouts rows for one date |
| `app/services/notion/red_flag_detector.rb` | Compute data-derived daily red flags |
| `app/services/notion/workout_commentary_generator.rb` | LLM → workout page body |
| `app/services/notion/daily_log_commentary_generator.rb` | LLM → Daily Logs `Notes` + merged Red Flags |
| `app/services/notion/weekly_review_generator.rb` | Aggregates + LLM → Weekly Reviews row |
| `app/jobs/notion_sync_job.rb` | Orchestrate sync for rolling window (yesterday + today PT) |
| `app/jobs/workout_commentary_job.rb` | One-shot commentary per newly synced workout |
| `app/jobs/daily_log_commentary_job.rb` | 10pm PT daily |
| `app/jobs/weekly_review_job.rb` | Sunday 9pm PT |
| `app/controllers/api/v1/health_data_controller.rb` | + enqueue `NotionSyncJob` on success |
| `config/recurring.yml` | + three recurring entries (commented until rollout) |

---

### Task 1: Migration — `notion_page_id` on workouts

**Files:**
- Create: `db/migrate/<timestamp>_add_notion_page_id_to_workouts.rb` (via generator)

- [ ] **Step 1: Generate and edit migration**

Run: `bin/rails generate migration AddNotionPageIdToWorkouts`

```ruby
class AddNotionPageIdToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :notion_page_id, :string
    add_index :workouts, :notion_page_id
  end
end
```

- [ ] **Step 2: Migrate and verify**

Run: `bin/rails db:migrate`
Expected: migration runs; `db/schema.rb` gains `notion_page_id` + index on workouts.

- [ ] **Step 3: Run full test suite to confirm nothing broke**

Run: `bin/rails test`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "feat: add notion_page_id to workouts"
```

---

### Task 2: `Notion::Properties`

**Files:**
- Create: `app/services/notion/properties.rb`
- Test: `test/services/notion/properties_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"

class Notion::PropertiesTest < ActiveSupport::TestCase
  test "builds title, rich_text, number, date, select, multi_select, checkbox" do
    assert_equal({"title" => [{"text" => {"content" => "Hi"}}]}, Notion::Properties.title("Hi"))
    assert_equal({"rich_text" => [{"text" => {"content" => "note"}}]}, Notion::Properties.rich_text("note"))
    assert_equal({"number" => 7.5}, Notion::Properties.number(7.5))
    assert_equal({"date" => {"start" => "2026-06-12"}}, Notion::Properties.date(Date.new(2026, 6, 12)))
    assert_equal({"select" => {"name" => "Easy Run"}}, Notion::Properties.select("Easy Run"))
    assert_equal({"multi_select" => [{"name" => "RHR up"}, {"name" => "HRV down"}]},
      Notion::Properties.multi_select(["RHR up", "HRV down"]))
    assert_equal({"checkbox" => true}, Notion::Properties.checkbox(true))
  end

  test "rich_text truncates to 2000 chars" do
    prop = Notion::Properties.rich_text("x" * 3000)
    assert_equal 2000, prop["rich_text"].first["text"]["content"].length
  end

  test "reads values from page property JSON" do
    assert_equal "Planned", Notion::Properties.read_select({"select" => {"name" => "Planned"}})
    assert_nil Notion::Properties.read_select({"select" => nil})
    assert_equal ["RHR up"], Notion::Properties.read_multi_select({"multi_select" => [{"name" => "RHR up"}]})
    assert_equal [], Notion::Properties.read_multi_select(nil)
    assert_equal 5.0, Notion::Properties.read_number({"number" => 5.0})
    assert_equal "W1 Fri - 5km Easy Run",
      Notion::Properties.read_title({"title" => [{"plain_text" => "W1 Fri - 5km Easy Run"}]})
    assert_equal "2026-06-12", Notion::Properties.read_date({"date" => {"start" => "2026-06-12"}})
  end

  test "paragraph_block builds a body block and truncates" do
    block = Notion::Properties.paragraph_block("hello")
    assert_equal "paragraph", block["type"]
    assert_equal "hello", block.dig("paragraph", "rich_text", 0, "text", "content")
  end
end
```

- [ ] **Step 2: Run to verify failure** — `bin/rails test test/services/notion/properties_test.rb` → fails (uninitialized constant).

- [ ] **Step 3: Implement**

```ruby
module Notion
  module Properties
    TEXT_LIMIT = 2000

    module_function

    def title(text) = {"title" => [{"text" => {"content" => text.to_s[0, TEXT_LIMIT]}}]}

    def rich_text(text) = {"rich_text" => [{"text" => {"content" => text.to_s[0, TEXT_LIMIT]}}]}

    def number(value) = {"number" => value&.to_f}

    def date(d) = {"date" => {"start" => d.iso8601}}

    def select(name) = {"select" => {"name" => name}}

    def multi_select(names) = {"multi_select" => names.map { |n| {"name" => n} }}

    def checkbox(value) = {"checkbox" => !!value}

    def paragraph_block(text)
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => {"rich_text" => [{"text" => {"content" => text.to_s[0, TEXT_LIMIT]}}]}
      }
    end

    def read_select(prop) = prop&.dig("select", "name")

    def read_multi_select(prop) = Array(prop&.dig("multi_select")).map { |o| o["name"] }

    def read_number(prop) = prop&.dig("number")

    def read_title(prop) = Array(prop&.dig("title")).map { |t| t["plain_text"] }.join

    def read_date(prop) = prop&.dig("date", "start")
  end
end
```

- [ ] **Step 4: Run tests** — same command → PASS.

- [ ] **Step 5: Commit** — `git add app/services/notion test/services/notion` then `git commit -m "feat: add Notion property builders/readers"`

---

### Task 3: `Notion::Client`

**Files:**
- Create: `app/services/notion/client.rb`
- Test: `test/services/notion/client_test.rb`

Design: public methods build paths/bodies and delegate to a private `request(method, path, body)`; tests stub `request` (codebase convention — no WebMock).

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"

class Notion::ClientTest < ActiveSupport::TestCase
  setup do
    @client = Notion::Client.new(token: "secret")
    @calls = []
    calls = @calls
    @responses = []
    responses = @responses
    @client.define_singleton_method(:request) do |method, path, body|
      calls << [method, path, body]
      responses.shift || {"results" => [], "has_more" => false}
    end
  end

  test "query_data_source posts filter and paginates" do
    @responses << {"results" => [{"id" => "p1"}], "has_more" => true, "next_cursor" => "abc"}
    @responses << {"results" => [{"id" => "p2"}], "has_more" => false}

    filter = {"property" => "Date", "date" => {"equals" => "2026-06-12"}}
    results = @client.query_data_source("ds-1", filter: filter)

    assert_equal %w[p1 p2], results.map { |r| r["id"] }
    assert_equal [:post, "/data_sources/ds-1/query", {"filter" => filter}], @calls[0]
    assert_equal "abc", @calls[1][2]["start_cursor"]
  end

  test "create_page targets data source parent and includes children when given" do
    @responses << {"id" => "new-page"}
    @client.create_page(data_source_id: "ds-1", properties: {"Day" => {}}, children: [{"type" => "paragraph"}])

    method, path, body = @calls[0]
    assert_equal :post, method
    assert_equal "/pages", path
    assert_equal({"type" => "data_source_id", "data_source_id" => "ds-1"}, body["parent"])
    assert body.key?("children")
  end

  test "update_page patches properties" do
    @responses << {"id" => "p1"}
    @client.update_page("p1", properties: {"RHR" => {"number" => 52}})
    assert_equal [:patch, "/pages/p1", {"properties" => {"RHR" => {"number" => 52}}}], @calls[0]
  end

  test "append_blocks patches block children" do
    @responses << {"results" => []}
    @client.append_blocks("p1", children: [{"type" => "paragraph"}])
    assert_equal :patch, @calls[0][0]
    assert_equal "/blocks/p1/children", @calls[0][1]
  end
end
```

- [ ] **Step 2: Run to verify failure** — `bin/rails test test/services/notion/client_test.rb` → fails.

- [ ] **Step 3: Implement**

```ruby
require "net/http"

module Notion
  class Client
    Error = Class.new(StandardError)

    BASE_URL = "https://api.notion.com/v1"
    API_VERSION = "2025-09-03"

    def initialize(token: ENV.fetch("NOTION_API_TOKEN"))
      @token = token
    end

    def query_data_source(data_source_id, filter: nil)
      results = []
      cursor = nil
      loop do
        body = {}
        body["filter"] = filter if filter
        body["start_cursor"] = cursor if cursor
        response = request(:post, "/data_sources/#{data_source_id}/query", body)
        results.concat(response["results"])
        break unless response["has_more"]
        cursor = response["next_cursor"]
      end
      results
    end

    def create_page(data_source_id:, properties:, children: nil)
      body = {
        "parent" => {"type" => "data_source_id", "data_source_id" => data_source_id},
        "properties" => properties
      }
      body["children"] = children if children
      request(:post, "/pages", body)
    end

    def update_page(page_id, properties:)
      request(:patch, "/pages/#{page_id}", {"properties" => properties})
    end

    def append_blocks(page_id, children:)
      request(:patch, "/blocks/#{page_id}/children", {"children" => children})
    end

    private

    def request(method, path, body)
      uri = URI("#{BASE_URL}#{path}")
      request_class = (method == :post) ? Net::HTTP::Post : Net::HTTP::Patch
      req = request_class.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Notion-Version"] = API_VERSION
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      parsed = JSON.parse(response.body)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Notion API #{response.code} on #{method.to_s.upcase} #{path}: #{parsed["message"]}"
      end
      parsed
    end
  end
end
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Live smoke test against the real API.** This validates the `2025-09-03` data-source endpoints and the integration's database access **before** building on them.

Run:
```bash
bash -c 'set -a; . .env; set +a; bin/rails runner "puts Notion::Client.new.query_data_source(ENV.fetch(\"NOTION_DAILY_LOGS_DS_ID\"), filter: {\"property\" => \"Date\", \"date\" => {\"equals\" => \"2026-06-11\"}}).map { |p| Notion::Properties.read_title(p[\"properties\"][\"Day\"]) }"'
```
Expected: prints `Thu Jun 11 (W6 D4) - Rest` (the known existing page). **If this 404s or 400s, STOP and fix the client/API version before proceeding** — likely causes: databases not shared with the integration, or data-source endpoints differ; fall back to `Notion-Version: 2022-06-28` with `/databases/{database_id}/query` and `parent: {"database_id": ...}` (database IDs: daily `8dfee80e53554d8188bd9aa9547aae9a`, workouts `4dc78a52d00b4d47aecd219edaa4d838`, weekly `07264ddf988e447197cc8b29935820bb`).

- [ ] **Step 6: Commit** — `git commit -m "feat: add minimal Notion REST client"`

---

### Task 4: `Notion::TrainingWeek`

**Files:**
- Create: `app/services/notion/training_week.rb`
- Test: `test/services/notion/training_week_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"

class Notion::TrainingWeekTest < ActiveSupport::TestCase
  W1 = Date.new(2026, 5, 4) # Monday

  test "computes week and day numbers" do
    tw = Notion::TrainingWeek.new(Date.new(2026, 6, 11), week1_start: W1) # known: W6 D4
    assert_equal 6, tw.week_number
    assert_equal 4, tw.day_number
    assert_equal Date.new(2026, 6, 8), tw.week_start
    assert_equal "W6 D4", tw.label
  end

  test "first day of plan is W1 D1" do
    tw = Notion::TrainingWeek.new(W1, week1_start: W1)
    assert_equal "W1 D1", tw.label
  end

  test "daily log title format" do
    tw = Notion::TrainingWeek.new(Date.new(2026, 6, 11), week1_start: W1)
    assert_equal "Thu Jun 11 (W6 D4) - Rest", tw.daily_title("Rest")
  end

  test "today returns a date in Pacific time" do
    assert_instance_of Date, Notion::TrainingWeek.today
  end
end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

```ruby
module Notion
  class TrainingWeek
    TIME_ZONE = "America/Los_Angeles"

    def self.today
      Time.now.in_time_zone(TIME_ZONE).to_date
    end

    def self.day_range(date)
      tz = ActiveSupport::TimeZone[TIME_ZONE]
      tz.local(date.year, date.month, date.day).all_day
    end

    def initialize(date, week1_start: Date.parse(ENV.fetch("TRAINING_WEEK1_START")))
      @date = date
      @week1_start = week1_start
    end

    attr_reader :date

    def week_number = ((@date - @week1_start).to_i / 7) + 1

    def day_number = ((@date - @week1_start).to_i % 7) + 1

    def week_start = @week1_start + ((week_number - 1) * 7)

    def label = "W#{week_number} D#{day_number}"

    def daily_title(day_type)
      "#{@date.strftime("%a %b %-d")} (#{label}) - #{day_type}"
    end
  end
end
```

- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: add training week numbering"`

---

### Task 5: `Notion::DailyLogSync`

**Files:**
- Create: `app/services/notion/daily_log_sync.rb`
- Test: `test/services/notion/daily_log_sync_test.rb`

Behavior (from spec):
- Find the row by `Date` equals; **update** data fields if found, **create** (with generated title + Date + Day Type) if not.
- Data fields: latest-of-day `weight` → `Weight (kg)`, `sleep_analysis` → `Sleep Hours`, `heart_rate_variability` → `HRV`, `resting_heart_rate` → `RHR`; sum-of-day `active_energy + basal_energy_burned` → `Calories Burned`; `food_logs` sums → `Calories Actual` / `Protein (g)` / `Fat (g)` / `Carbs (g)`; alcohol grams ÷ 14 rounded to 0.5 → `Alcohol (drinks)`; `nutrition_profiles.calorie_target` → `Calories Target`; `Deficit` = Actual − Burned (only when both present).
- **Omit properties whose value is nil/absent** — never write null over a human-entered value.
- `Day Type`: on create, set from `day_type:` arg (default `"Rest"`). On update, upgrade only — write it when the new type outranks the page's current value on the rank Rest < Golf < Strength < Easy Run < Hard Run < Long Run (empty counts as lowest); never write when the current value is unranked/human-set (e.g. `Travel`) or outranks the new type. Title is set on create only — never updated (humans customize titles).
- Human-owned, never in any payload: `Mood`, `Sleep Score`, `Withdrawal Bleed`, `Notes` (Notes belongs to the commentary generator), `Red Flags` (belongs to the commentary pass).
- All date bucketing via `TrainingWeek.day_range(date)` (PT).

Test hygiene note (applies to Tasks 5–10): tests set `ENV` keys in `setup`; capture originals and restore them in `teardown` to avoid cross-test leakage.

- [ ] **Step 1: Write failing tests** (use a `FakeNotionClient` — define once in `test/services/notion/fake_notion_client.rb` and reuse in later tasks)

```ruby
# test/services/notion/fake_notion_client.rb
class FakeNotionClient
  attr_reader :queries, :creates, :updates, :appends

  def initialize(query_results: [])
    @query_results = query_results # array of arrays, shifted per call
    @queries = []
    @creates = []
    @updates = []
    @appends = []
  end

  def query_data_source(ds_id, filter: nil)
    @queries << {ds_id: ds_id, filter: filter}
    @query_results.shift || []
  end

  def create_page(data_source_id:, properties:, children: nil)
    @creates << {ds_id: data_source_id, properties: properties, children: children}
    {"id" => "created-#{@creates.size}", "properties" => properties}
  end

  def update_page(page_id, properties:)
    @updates << {page_id: page_id, properties: properties}
    {"id" => page_id}
  end

  def append_blocks(page_id, children:)
    @appends << {page_id: page_id, children: children}
    {"results" => []}
  end
end
```

```ruby
require "test_helper"
require_relative "fake_notion_client"

class Notion::DailyLogSyncTest < ActiveSupport::TestCase
  DATE = Date.new(2026, 6, 11)

  setup do
    @user = users(:one)
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_DAILY_LOGS_DS_ID"] = "ds-daily"
    noon_pt = ActiveSupport::TimeZone["America/Los_Angeles"].local(2026, 6, 11, 12)
    @user.health_metrics.create!(metric_name: "weight", value: 61.2, units: "kg", recorded_at: noon_pt)
    @user.health_metrics.create!(metric_name: "active_energy", value: 500, units: "kcal", recorded_at: noon_pt)
    @user.health_metrics.create!(metric_name: "basal_energy_burned", value: 1300, units: "kcal", recorded_at: noon_pt)
    food = @user.foods.create!(description: "test food", kcal: 1)
    @user.food_logs.create!(food: food, consumed_at: noon_pt, kcal: 1650, protein: 140, fat: 50, carbs: 160, alcohol: 21)
  end

  test "creates page with generated title, date, day type, and data fields when none exists" do
    client = FakeNotionClient.new(query_results: [[]])
    result = Notion::DailyLogSync.call(@user, date: DATE, day_type: "Easy Run", client: client)

    assert result.success
    assert result.created
    props = client.creates.first[:properties]
    assert_equal "Thu Jun 11 (W6 D4) - Easy Run", props["Day"]["title"].first["text"]["content"]
    assert_equal "2026-06-11", props["Date"]["date"]["start"]
    assert_equal "Easy Run", props["Day Type"]["select"]["name"]
    assert_equal 61.2, props["Weight (kg)"]["number"]
    assert_equal 1800.0, props["Calories Burned"]["number"]
    assert_equal 1650.0, props["Calories Actual"]["number"]
    assert_equal(-150.0, props["Deficit"]["number"])
    assert_equal 1.5, props["Alcohol (drinks)"]["number"]  # 21g / 14 = 1.5
  end

  test "updates existing page without touching human-owned fields or title" do
    existing = {"id" => "page-1", "properties" => {"Day Type" => {"select" => {"name" => "Rest"}}}}
    client = FakeNotionClient.new(query_results: [[existing]])

    result = Notion::DailyLogSync.call(@user, date: DATE, day_type: "Long Run", client: client)

    assert result.success
    refute result.created
    update = client.updates.first
    assert_equal "page-1", update[:page_id]
    props = update[:properties]
    refute props.key?("Day")
    refute props.key?("Mood")
    refute props.key?("Notes")
    refute props.key?("Red Flags")
    assert_equal "Long Run", props["Day Type"]["select"]["name"] # Rest -> Long Run upgrade
  end

  test "does not downgrade or overwrite a human-set day type" do
    existing = {"id" => "page-1", "properties" => {"Day Type" => {"select" => {"name" => "Travel"}}}}
    client = FakeNotionClient.new(query_results: [[existing]])

    Notion::DailyLogSync.call(@user, date: DATE, day_type: "Easy Run", client: client)

    refute client.updates.first[:properties].key?("Day Type")
  end

  test "omits properties with no data" do
    client = FakeNotionClient.new(query_results: [[]])
    @user.health_metrics.delete_all
    @user.food_logs.delete_all

    Notion::DailyLogSync.call(@user, date: DATE, client: client)

    props = client.creates.first[:properties]
    refute props.key?("Weight (kg)")
    refute props.key?("Deficit")
  end

  test "returns failure result on client error" do
    client = FakeNotionClient.new
    def client.query_data_source(*) = raise(Notion::Client::Error, "boom")

    result = Notion::DailyLogSync.call(@user, date: DATE, client: client)

    refute result.success
    assert_match "boom", result.error
  end
end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

```ruby
module Notion
  class DailyLogSync
    Result = Struct.new(:success, :page_id, :created, :error, keyword_init: true)

    GRAMS_PER_DRINK = 14.0
    DAY_TYPE_RANK = ["Rest", "Golf", "Strength", "Easy Run", "Hard Run", "Long Run"].freeze

    def self.call(user, date:, day_type: nil, client: Client.new)
      new(user, date: date, day_type: day_type, client: client).call
    end

    def initialize(user, date:, day_type:, client:)
      @user = user
      @date = date
      @day_type = day_type || "Rest"
      @client = client
    end

    def call
      page = find_page
      if page
        properties = data_properties
        if upgrade_day_type?(Properties.read_select(page["properties"]["Day Type"]))
          properties["Day Type"] = Properties.select(@day_type)
        end
        @client.update_page(page["id"], properties: properties)
        Result.new(success: true, page_id: page["id"], created: false)
      else
        properties = data_properties
        properties["Day"] = Properties.title(training_week.daily_title(@day_type))
        properties["Date"] = Properties.date(@date)
        properties["Day Type"] = Properties.select(@day_type)
        response = @client.create_page(data_source_id: ds_id, properties: properties)
        Result.new(success: true, page_id: response["id"], created: true)
      end
    rescue => e
      Rails.logger.error("Notion::DailyLogSync failed for #{@date}: #{e.class}: #{e.message}")
      Result.new(success: false, error: e.message)
    end

    private

    def ds_id = ENV.fetch("NOTION_DAILY_LOGS_DS_ID")

    def training_week = TrainingWeek.new(@date)

    def find_page
      @client.query_data_source(ds_id,
        filter: {"property" => "Date", "date" => {"equals" => @date.iso8601}}).first
    end

    def upgrade_day_type?(current)
      return false if @day_type == "Rest"
      current_rank = DAY_TYPE_RANK.index(current)
      new_rank = DAY_TYPE_RANK.index(@day_type)
      return false if new_rank.nil?
      current.blank? || (current_rank && new_rank > current_rank)
    end

    def data_properties
      props = {}
      props["Weight (kg)"] = Properties.number(latest_metric("weight")) if latest_metric("weight")
      props["Sleep Hours"] = Properties.number(latest_metric("sleep_analysis")) if latest_metric("sleep_analysis")
      props["HRV"] = Properties.number(latest_metric("heart_rate_variability")) if latest_metric("heart_rate_variability")
      props["RHR"] = Properties.number(latest_metric("resting_heart_rate")) if latest_metric("resting_heart_rate")

      burned = sum_metric("active_energy") + sum_metric("basal_energy_burned")
      props["Calories Burned"] = Properties.number(burned.round) if burned.positive?

      food = @user.food_logs.where(consumed_at: day_range)
      if food.exists?
        actual = food.sum(:kcal).to_f
        props["Calories Actual"] = Properties.number(actual.round)
        props["Protein (g)"] = Properties.number(food.sum(:protein).round)
        props["Fat (g)"] = Properties.number(food.sum(:fat).round)
        props["Carbs (g)"] = Properties.number(food.sum(:carbs).round)
        props["Deficit"] = Properties.number((actual - burned).round) if burned.positive?

        alcohol_grams = food.sum(:alcohol).to_f
        if alcohol_grams.positive?
          props["Alcohol (drinks)"] = Properties.number(((alcohol_grams / GRAMS_PER_DRINK) * 2).round / 2.0)
        end
      end

      target = @user.nutrition_profile&.calorie_target
      props["Calories Target"] = Properties.number(target) if target
      props
    end

    def day_range = TrainingWeek.day_range(@date)

    def latest_metric(name)
      @latest ||= {}
      @latest[name] ||= @user.health_metrics
        .where(metric_name: name, recorded_at: day_range)
        .order(recorded_at: :desc).first&.value&.to_f
    end

    def sum_metric(name)
      @user.health_metrics.where(metric_name: name, recorded_at: day_range).sum(:value).to_f
    end
  end
end
```

Note: confirm `User` has `has_one :nutrition_profile` (check `app/models/user.rb`; adjust accessor if the association is named differently).

- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: add Notion daily log sync"`

---

### Task 6: `Notion::WorkoutSync`

**Files:**
- Create: `app/services/notion/workout_sync.rb`
- Test: `test/services/notion/workout_sync_test.rb`

Behavior (from spec):
- For each DB workout with `started_at` in the PT date:
  - If `notion_page_id` present → update actuals on that page (no status change, no commentary).
  - Else query Workouts DS for rows with `Date` equals the date; candidates are rows whose `Status` is `Planned` or `Modified` (never `Skipped`/`Done`) and whose `Type` is compatible with the Apple `workout_type`. Match first candidate; fill actuals + `Status: Done`; persist `notion_page_id`; record as newly synced.
  - Else create a new row: `Session` = `"W{n} {Dow} - {workout_type} (unplanned)"`, `Date`, `Type` mapped, `Status: Done`, `Week`, actuals; persist `notion_page_id`; record as newly synced.
- Returns `Result(success:, newly_synced_workout_ids:, day_type:, error:)`. `day_type` = highest-ranked Day Type across the date's workouts (from the matched Notion `Type` when available, else from `workout_type`), nil if no workouts.
- Actuals mapping: distance→km via `distance_units` (`km` as-is, `mi` ×1.609344, `m` ÷1000), duration→minutes (1 dp), avg HR from `metadata["heartRate"]["avg"]` (rounded), pace `mm:ss/km` from duration÷km, `kCal Burned` from `energy_burned` (rounded). Omit nil actuals.
- Human-owned, never in payloads: `Felt`, `RPE`, `Fueled Properly`, `Hit Prescribed Pace`, `Notes`, `Planned Description`, `Planned Distance (km)`.

Type compatibility and day-type maps:

```ruby
RUN_NOTION_TYPES = %w[Easy Quality Long Race].freeze

def compatible_notion_types(workout_type)
  case workout_type
  when /running/i then RUN_NOTION_TYPES
  when /strength/i then ["Strength"]
  when /golf/i then ["Golf"]
  when /cycling|swimming|elliptical|rower|rowing/i then ["Cross"]
  else []
  end
end

DAY_TYPE_FOR_NOTION_TYPE = {
  "Long" => "Long Run", "Quality" => "Hard Run", "Race" => "Hard Run",
  "Easy" => "Easy Run", "Strength" => "Strength", "Golf" => "Golf"
}.freeze
```

- [ ] **Step 1: Write failing tests**

```ruby
require "test_helper"
require_relative "fake_notion_client"

class Notion::WorkoutSyncTest < ActiveSupport::TestCase
  DATE = Date.new(2026, 6, 11)

  setup do
    @user = users(:one)
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_WORKOUTS_DS_ID"] = "ds-workouts"
    @started = ActiveSupport::TimeZone["America/Los_Angeles"].local(2026, 6, 11, 7)
  end

  def create_run(attrs = {})
    @user.workouts.create!({
      external_id: SecureRandom.uuid, workout_type: "Running",
      started_at: @started, ended_at: @started + 35.minutes, duration: 2100,
      distance: 5.0, distance_units: "km", energy_burned: 410.4,
      metadata: {"heartRate" => {"avg" => 152.3, "min" => 110, "max" => 171}}
    }.merge(attrs))
  end

  def planned_row(id: "plan-1", type: "Easy", status: "Planned")
    {"id" => id, "properties" => {
      "Type" => {"select" => {"name" => type}},
      "Status" => {"select" => {"name" => status}}
    }}
  end

  test "matches a planned run, fills actuals, sets Done, stores page id" do
    workout = create_run
    client = FakeNotionClient.new(query_results: [[planned_row]])

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert result.success
    assert_equal [workout.id], result.newly_synced_workout_ids
    assert_equal "Easy Run", result.day_type
    assert_equal "plan-1", workout.reload.notion_page_id

    props = client.updates.first[:properties]
    assert_equal 5.0, props["Actual Distance (km)"]["number"]
    assert_equal 35.0, props["Actual Duration (min)"]["number"]
    assert_equal 152.0, props["Actual Avg HR"]["number"]
    assert_equal "7:00/km", props["Actual Avg Pace"]["rich_text"].first["text"]["content"]
    assert_equal 410.0, props["kCal Burned"]["number"]
    assert_equal "Done", props["Status"]["select"]["name"]
    refute props.key?("Felt")
    refute props.key?("Notes")
  end

  test "ignores Skipped and Done rows as candidates and creates unplanned row" do
    workout = create_run(workout_type: "Golf", distance: nil, distance_units: nil, metadata: {})
    client = FakeNotionClient.new(query_results: [[planned_row(status: "Skipped", type: "Golf")]])

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_empty client.updates
    create = client.creates.first
    props = create[:properties]
    assert_equal "W6 Thu - Golf (unplanned)", props["Session"]["title"].first["text"]["content"]
    assert_equal "Golf", props["Type"]["select"]["name"]
    assert_equal "Done", props["Status"]["select"]["name"]
    assert_equal 6.0, props["Week"]["number"]
    assert_equal "created-1", workout.reload.notion_page_id
    assert_equal "Golf", result.day_type
  end

  test "already-linked workout updates its page without re-matching or re-announcing" do
    workout = create_run(notion_page_id: "page-9")
    client = FakeNotionClient.new

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_empty client.queries          # no matching query needed
    assert_equal "page-9", client.updates.first[:page_id]
    refute client.updates.first[:properties].key?("Status")
    assert_empty result.newly_synced_workout_ids
  end

  test "converts miles to km" do
    create_run(distance: 3.1, distance_units: "mi")
    client = FakeNotionClient.new(query_results: [[planned_row]])

    Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_in_delta 4.99, client.updates.first[:properties]["Actual Distance (km)"]["number"], 0.01
  end

  test "long run outranks easy for day_type" do
    create_run
    create_run(started_at: @started + 8.hours, ended_at: @started + 9.hours)
    client = FakeNotionClient.new(query_results: [[planned_row(id: "p1", type: "Easy"), planned_row(id: "p2", type: "Long")], []])

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_equal "Long Run", result.day_type
  end

  test "no workouts returns nil day_type and success" do
    client = FakeNotionClient.new
    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)
    assert result.success
    assert_nil result.day_type
    assert_empty result.newly_synced_workout_ids
  end
end
```

Note on the multi-candidate test: the implementation must consume **one candidate per workout** (a second workout on the same date must not match the same row twice — track claimed page IDs within the run; the fake returns the remaining list on the second query OR the service queries once and consumes locally — implement the latter: query once per date, consume candidates as they're claimed).

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** (complete code)

```ruby
module Notion
  class WorkoutSync
    Result = Struct.new(:success, :newly_synced_workout_ids, :day_type, :error, keyword_init: true)

    RUN_NOTION_TYPES = %w[Easy Quality Long Race].freeze
    DAY_TYPE_FOR_NOTION_TYPE = {
      "Long" => "Long Run", "Quality" => "Hard Run", "Race" => "Hard Run",
      "Easy" => "Easy Run", "Strength" => "Strength", "Golf" => "Golf"
    }.freeze
    MI_TO_KM = 1.609344

    def self.call(user, date:, client: Client.new)
      new(user, date: date, client: client).call
    end

    def initialize(user, date:, client:)
      @user = user
      @date = date
      @client = client
      @newly_synced = []
      @day_types = []
    end

    def call
      workouts = @user.workouts.where(started_at: TrainingWeek.day_range(@date)).order(:started_at)
      workouts.each { |workout| sync_workout(workout) }
      Result.new(success: true, newly_synced_workout_ids: @newly_synced, day_type: top_day_type)
    rescue => e
      Rails.logger.error("Notion::WorkoutSync failed for #{@date}: #{e.class}: #{e.message}")
      Result.new(success: false, newly_synced_workout_ids: @newly_synced, day_type: top_day_type, error: e.message)
    end

    private

    def ds_id = ENV.fetch("NOTION_WORKOUTS_DS_ID")

    def sync_workout(workout)
      if workout.notion_page_id.present?
        @client.update_page(workout.notion_page_id, properties: actuals(workout))
        record_day_type(linked_notion_type(workout) || fallback_day_type(workout))
        return
      end

      candidate = claim_candidate(workout)
      if candidate
        @client.update_page(candidate["id"],
          properties: actuals(workout).merge("Status" => Properties.select("Done")))
        workout.update!(notion_page_id: candidate["id"])
        record_day_type(DAY_TYPE_FOR_NOTION_TYPE[Properties.read_select(candidate["properties"]["Type"])])
      else
        response = @client.create_page(data_source_id: ds_id, properties: unplanned_properties(workout))
        workout.update!(notion_page_id: response["id"])
        record_day_type(fallback_day_type(workout))
      end
      @newly_synced << workout.id
    end

    def candidates
      @candidates ||= @client.query_data_source(ds_id,
        filter: {"property" => "Date", "date" => {"equals" => @date.iso8601}})
        .select { |row| %w[Planned Modified].include?(Properties.read_select(row["properties"]["Status"])) }
    end

    def claim_candidate(workout)
      types = compatible_notion_types(workout.workout_type)
      match = candidates.find { |row| types.include?(Properties.read_select(row["properties"]["Type"])) }
      @candidates.delete(match) if match
      match
    end

    def compatible_notion_types(workout_type)
      case workout_type
      when /running/i then RUN_NOTION_TYPES
      when /strength/i then ["Strength"]
      when /golf/i then ["Golf"]
      when /cycling|swimming|elliptical|rower|rowing/i then ["Cross"]
      else []
      end
    end

    def actuals(workout)
      props = {}
      km = distance_km(workout)
      props["Actual Distance (km)"] = Properties.number(km.round(2)) if km
      props["Actual Duration (min)"] = Properties.number((workout.duration / 60.0).round(1))
      avg_hr = workout.metadata&.dig("heartRate", "avg")
      props["Actual Avg HR"] = Properties.number(avg_hr.round) if avg_hr
      props["Actual Avg Pace"] = Properties.rich_text(pace(workout, km)) if km&.positive?
      props["kCal Burned"] = Properties.number(workout.energy_burned.round) if workout.energy_burned
      props
    end

    def distance_km(workout)
      return nil unless workout.distance
      case workout.distance_units
      when "mi" then workout.distance.to_f * MI_TO_KM
      when "m" then workout.distance.to_f / 1000
      else workout.distance.to_f
      end
    end

    def pace(workout, km)
      seconds_per_km = workout.duration / km
      format("%d:%02d/km", seconds_per_km / 60, (seconds_per_km % 60).round)
    end

    def unplanned_properties(workout)
      week = TrainingWeek.new(@date)
      type = fallback_notion_type(workout)
      props = actuals(workout)
      props["Session"] = Properties.title("W#{week.week_number} #{@date.strftime("%a")} - #{workout.workout_type} (unplanned)")
      props["Date"] = Properties.date(@date)
      props["Status"] = Properties.select("Done")
      props["Week"] = Properties.number(week.week_number)
      props["Type"] = Properties.select(type) if type
      props
    end

    def fallback_notion_type(workout)
      case workout.workout_type
      when /running/i then "Easy"
      when /strength/i then "Strength"
      when /golf/i then "Golf"
      when /cycling|swimming|elliptical|rower|rowing/i then "Cross"
      end
    end

    def fallback_day_type(workout)
      DAY_TYPE_FOR_NOTION_TYPE[fallback_notion_type(workout)]
    end

    def linked_notion_type(_workout) = nil # linked pages aren't re-fetched; day type falls back

    def record_day_type(day_type)
      @day_types << day_type if day_type
    end

    def top_day_type
      @day_types.max_by { |t| DailyLogSync::DAY_TYPE_RANK.index(t) || -1 }
    end
  end
end
```

- [ ] **Step 4: Run tests** → PASS (also rerun daily log sync tests — `bin/rails test test/services/notion/`).
- [ ] **Step 5: Commit** — `git commit -m "feat: add Notion workout match-and-fill sync"`

---

### Task 7: `NotionSyncJob` + webhook chaining + recurring entry

**Files:**
- Create: `app/jobs/notion_sync_job.rb`, `test/jobs/notion_sync_job_test.rb`
- Modify: `app/controllers/api/v1/health_data_controller.rb` (enqueue on success), `test/controllers/api/v1/health_data_controller_test.rb` (assert enqueue)
- Modify: `config/recurring.yml` (commented entry)

- [ ] **Step 1: Write failing job test**

```ruby
require "test_helper"
require_relative "../services/notion/fake_notion_client"

class NotionSyncJobTest < ActiveJob::TestCase
  setup do
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_DAILY_LOGS_DS_ID"] = "ds-daily"
    ENV["NOTION_WORKOUTS_DS_ID"] = "ds-workouts"
    @user = users(:one)
    @user.update!(email: "jules@julescoleman.com")
  end

  test "syncs workouts then daily log for yesterday and today, enqueues commentary for new syncs" do
    calls = []
    workout_result = Notion::WorkoutSync::Result.new(
      success: true, newly_synced_workout_ids: [42], day_type: "Easy Run")
    daily_result = Notion::DailyLogSync::Result.new(success: true, page_id: "p", created: false)

    Notion::WorkoutSync.stub(:call, ->(user, date:, client:) { calls << [:workout, date]; workout_result }) do
      Notion::DailyLogSync.stub(:call, ->(user, date:, day_type:, client:) { calls << [:daily, date, day_type]; daily_result }) do
        NotionSyncJob.perform_now
      end
    end

    today = Notion::TrainingWeek.today
    assert_equal [:workout, today - 1], calls[0]
    assert_equal [:daily, today - 1, "Easy Run"], calls[1]
    assert_equal [:workout, today], calls[2]
    assert_enqueued_with(job: WorkoutCommentaryJob, args: [42])
  end
end
```

(`Minitest::Mock`/`.stub` is available via `minitest` bundled with Rails. `WorkoutCommentaryJob` doesn't exist yet — create an empty shell in this task; its real body comes in Task 8.)

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement job + empty commentary job shell**

```ruby
class NotionSyncJob < ApplicationJob
  limits_concurrency to: 1, key: "notion_sync"

  def perform
    user = User.find_by!(email: "jules@julescoleman.com")
    client = Notion::Client.new
    today = Notion::TrainingWeek.today

    [today - 1, today].each do |date|
      workout_result = Notion::WorkoutSync.call(user, date: date, client: client)
      Notion::DailyLogSync.call(user, date: date, day_type: workout_result.day_type, client: client)
      workout_result.newly_synced_workout_ids.each do |workout_id|
        WorkoutCommentaryJob.perform_later(workout_id)
      end
    end
  end
end
```

```ruby
class WorkoutCommentaryJob < ApplicationJob
  def perform(workout_id)
    # implemented in Task 8
  end
end
```

- [ ] **Step 4: Run job tests** → PASS.

- [ ] **Step 5: Chain from webhook.** In `Api::V1::HealthDataController#create`, inside the `if result.success` branch, before `render`:

```ruby
NotionSyncJob.perform_later
```

Add to the existing controller test (`test/controllers/api/v1/health_data_controller_test.rb`): a successful POST enqueues `NotionSyncJob` (use `assert_enqueued_with(job: NotionSyncJob)`); a failed payload does not.

- [ ] **Step 6: Add commented recurring entry** to `config/recurring.yml` under `production:`:

```yaml
  # Enable after one-shot verification (see rollout in plan):
  # notion_catchup:
  #   class: NotionSyncJob
  #   schedule: every 30 minutes
```

- [ ] **Step 7: Run full suite** — `bin/rails test` → all green.
- [ ] **Step 8: Commit** — `git commit -m "feat: add NotionSyncJob with webhook chaining"`

---

### Task 8: Workout commentary (generator + job)

**Files:**
- Create: `app/services/notion/workout_commentary_generator.rb`, `test/services/notion/workout_commentary_generator_test.rb`
- Modify: `app/jobs/workout_commentary_job.rb`, create `test/jobs/workout_commentary_job_test.rb`

Behavior: one `RubyLLM.chat` call (copy `PlanSuggestionGenerator`'s structure and its test's `stub_llm_chat` helper — extract that helper into `test/support/llm_stubbing.rb` and require it from both tests if convenient, or duplicate it; prefer extracting). Context: the workout's actuals, the plan content, last 7 days of workouts. Output: 2-4 sentence coach commentary. Write via `client.append_blocks(workout.notion_page_id, children: [Properties.paragraph_block("🤖 Coach: " + text)])`.

Gate (from spec): the job is only ever enqueued by `WorkoutSync` for newly synced workouts — the generator itself does not check for prior commentary. A permanently failed job never re-fires; accepted.

- [ ] **Step 1: Write failing generator test** — assert: (a) success path appends one paragraph block to the workout's `notion_page_id` containing the LLM text; (b) prompt includes workout type, distance, and plan content; (c) LLM failure → `Result(success: false)` and **no** `append_blocks` call; (d) workout without `notion_page_id` → failure, no API call.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

```ruby
module Notion
  class WorkoutCommentaryGenerator
    Result = Struct.new(:success, :commentary, :error, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT
      You are a concise running coach reviewing a single completed workout for an athlete
      training for the SF Half Marathon. Given the workout's actual numbers, the training
      plan, and the recent week of training, write 2-4 sentences of commentary: how the
      session went relative to its purpose, anything notable (pace, HR, fatigue signals),
      and what it means for the next few days. No headers, no bullet points.
    PROMPT

    def self.call(workout, client: Client.new)
      new(workout, client: client).call
    end

    def initialize(workout, client:)
      @workout = workout
      @client = client
    end

    def call
      return Result.new(success: false, error: "workout has no notion_page_id") if @workout.notion_page_id.blank?

      response = RubyLLM.chat(model: ENV.fetch("LLM_MODEL", "gpt-5-nano"))
        .with_params(reasoning_effort: "medium")
        .with_instructions(SYSTEM_PROMPT)
        .ask(build_context)

      @client.append_blocks(@workout.notion_page_id,
        children: [Properties.paragraph_block("🤖 Coach: #{response.content}")])
      Result.new(success: true, commentary: response.content)
    rescue => e
      Rails.logger.error("Notion::WorkoutCommentaryGenerator failed for Workout##{@workout.id}: #{e.class}: #{e.message}")
      Result.new(success: false, error: e.message)
    end

    private

    def build_context
      user = @workout.user
      plan = user.plan
      recent = user.workouts.where(started_at: 7.days.ago..).where.not(id: @workout.id).order(:started_at)

      <<~CONTEXT
        ## This Workout
        #{format_workout(@workout)}

        ## Training Plan
        #{plan&.content || "No plan on file."}

        ## Last 7 Days
        #{recent.map { |w| format_workout(w) }.presence&.join("\n") || "No other workouts."}
      CONTEXT
    end

    def format_workout(w)
      parts = ["#{w.started_at.in_time_zone(TrainingWeek::TIME_ZONE).strftime("%a %b %-d")}: #{w.workout_type}"]
      parts << "#{(w.duration / 60.0).round} min"
      parts << "#{w.distance} #{w.distance_units}" if w.distance.present?
      parts << "avg HR #{w.metadata.dig("heartRate", "avg").round}" if w.metadata&.dig("heartRate", "avg")
      parts << "#{w.energy_burned.round} kcal" if w.energy_burned.present?
      parts.join(", ")
    end
  end
end
```

```ruby
class WorkoutCommentaryJob < ApplicationJob
  def perform(workout_id)
    workout = Workout.find(workout_id)
    result = Notion::WorkoutCommentaryGenerator.call(workout)
    unless result.success
      Rails.logger.error("WorkoutCommentaryJob failed for Workout##{workout_id}: #{result.error}")
    end
  end
end
```

Note: confirm `User has_one :plan` and `Workout belongs_to :user` accessors against the models; adjust if named differently.

- [ ] **Step 4: Run tests** → PASS.
- [ ] **Step 5: Commit** — `git commit -m "feat: add workout commentary generator and job"`

---

### Task 9: Red flags + daily log commentary (detector, generator, job, recurring entry)

**Files:**
- Create: `app/services/notion/red_flag_detector.rb`, `test/services/notion/red_flag_detector_test.rb`
- Create: `app/services/notion/daily_log_commentary_generator.rb`, `test/services/notion/daily_log_commentary_generator_test.rb`
- Create: `app/jobs/daily_log_commentary_job.rb`, `test/jobs/daily_log_commentary_job_test.rb`
- Modify: `config/recurring.yml`

**`Notion::RedFlagDetector`** — pure computation, `self.call(user, date:) -> Array<String>` of Daily Logs `Red Flags` option names:

```ruby
module Notion
  class RedFlagDetector
    RHR_DELTA_BPM = 5          # today's RHR this much above 7-day baseline
    HRV_DROP_RATIO = 0.8       # today's HRV below 80% of 7-day baseline
    SLEEP_MIN_HOURS = 6.5
    WEEKLY_WEIGHT_LOSS_KG = 1.0 # more than 1 kg lost vs 7 days ago

    def self.call(user, date:)
      new(user, date: date).call
    end

    def initialize(user, date:)
      @user = user
      @date = date
    end

    def call
      flags = []
      flags << "RHR up" if rhr_up?
      flags << "HRV down" if hrv_down?
      flags << "Sleep <6.5h" if sleep_short?
      flags << "Weight loss too fast" if weight_loss_too_fast?
      flags
    end

    private

    def day_value(name, date = @date)
      @user.health_metrics.where(metric_name: name, recorded_at: TrainingWeek.day_range(date))
        .order(recorded_at: :desc).first&.value&.to_f
    end

    def baseline(name)
      range = TrainingWeek.day_range(@date - 7).first..TrainingWeek.day_range(@date - 1).last
      values = @user.health_metrics.where(metric_name: name, recorded_at: range).pluck(:value)
      return nil if values.empty?
      values.sum.to_f / values.size
    end

    def rhr_up?
      today, base = day_value("resting_heart_rate"), baseline("resting_heart_rate")
      today && base && today >= base + RHR_DELTA_BPM
    end

    def hrv_down?
      today, base = day_value("heart_rate_variability"), baseline("heart_rate_variability")
      today && base && today <= base * HRV_DROP_RATIO
    end

    def sleep_short?
      sleep = day_value("sleep_analysis")
      sleep && sleep < SLEEP_MIN_HOURS
    end

    def weight_loss_too_fast?
      today = day_value("weight")
      week_ago = (1..3).lazy.map { |i| day_value("weight", @date - 7 - i + 1) }.find(&:itself) # nearest reading ~7 days back
      today && week_ago && (week_ago - today) > WEEKLY_WEIGHT_LOSS_KG
    end
  end
end
```

**`Notion::DailyLogCommentaryGenerator`** — `self.call(user, date:, client:)`:
1. Find the day's page (same query as `DailyLogSync`); if missing, run `DailyLogSync` first to create it, then re-query.
2. Build context: the day's metrics, food totals vs targets, the day's workouts, plan content, yesterday for comparison. One `RubyLLM.chat` call → one-paragraph narrative.
3. Compute `RedFlagDetector` flags; merge with the page's existing `Red Flags` (union, never remove).
4. `client.update_page(page_id, properties: {"Notes" => Properties.rich_text(narrative), "Red Flags" => Properties.multi_select(merged)})` — only include `Red Flags` when merged list differs from existing (avoid no-op churn).

**`DailyLogCommentaryJob`** — `perform` → hardcoded user, `Notion::TrainingWeek.today`, call generator, log on failure.

- [ ] **Step 1: Write failing detector tests** — cover: each flag trips at its threshold; no flags with no data; baselines ignore today's value.
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement detector.** Run tests → PASS.
- [ ] **Step 4: Write failing generator tests** — cover: (a) writes Notes with LLM text and merges red flags (existing `["Low mood"]` + computed `["RHR up"]` → both present); (b) never removes existing flags; (c) creates the daily page first when missing; (d) LLM failure → no update call, `success: false`. Use `FakeNotionClient` + the LLM stub helper.
- [ ] **Step 5: Run to verify failure.**
- [ ] **Step 6: Implement generator + job.** Run tests → PASS.
- [ ] **Step 7: Add commented recurring entry:**

```yaml
  # daily_log_commentary:
  #   class: DailyLogCommentaryJob
  #   schedule: "52 21 * * * America/Los_Angeles"   # 9:52pm PT daily
```

- [ ] **Step 8: Full suite** — `bin/rails test` → green.
- [ ] **Step 9: Commit** — `git commit -m "feat: add daily red flags and commentary generation"`

---

### Task 10: Weekly review (generator + job + recurring entry)

**Files:**
- Create: `app/services/notion/weekly_review_generator.rb`, `test/services/notion/weekly_review_generator_test.rb`
- Create: `app/jobs/weekly_review_job.rb`, `test/jobs/weekly_review_job_test.rb`
- Modify: `config/recurring.yml`

**`Notion::WeeklyReviewGenerator`** — `self.call(user, date:, client:)` where `date` is any day in the target week:

1. `week = TrainingWeek.new(date)`; week range = `week.week_start..week.week_start + 6`.
2. **Upsert by `Week Start`**: query Weekly Reviews DS for `Week Start` equals `week.week_start`; update if found, create if not (a Solid Queue retry must not duplicate).
3. Aggregates from the **Workouts DS** rows in the week range (one query, `Date` `on_or_after`/`on_or_before` compound filter):
   - `Planned km` = sum of `Planned Distance (km)` over all rows
   - `Actual km` = sum of `Actual Distance (km)` over `Done` rows
   - `Long Run Distance (km)` = max `Actual Distance (km)` among `Done` rows with Type `Long`
   - `Quality Session Done` = any `Done` row with Type `Quality`; `Strength Done` = any `Done` row with Type `Strength`
4. Aggregates from DB: `Avg HRV` / `Avg RHR` / `Avg Sleep Hours` (averages of daily values over the week), `Weight Start (kg)` / `Weight End (kg)` (first/last weight readings in the week).
5. `Red Flags Triggered` = union of the week's Daily Logs rows' `Red Flags` (query Daily Logs DS for the week range), mapped to Weekly option names (`"Sleep <6.5h"` → `"Sleep short"`; all other names match 1:1; drop any name not in the Weekly options list; add `"Multiple red flags"` when ≥3 distinct flags). Merge-only against existing.
6. LLM (one call): instructions demand **strict JSON** `{"status": "On Track|Cautious|Concern|Off Plan", "what_worked": "...", "what_broke": "...", "adjustment_for_next_week": "..."}` given context (aggregates, plan content, red flags, race countdown). Parse with `JSON.parse`; on parse failure or invalid status, fall back to status `"Cautious"` and put the raw text in `What Worked`. The model may wrap JSON in code fences — strip them before parsing (`response.content[/\{.*\}/m]`).
7. Title on create: `"W#{week.week_number} (#{week.week_start.strftime("%b %-d")} - #{(week.week_start + 6).strftime("%b %-d")})"`; `Week Number`, `Week Start` set on create.

**`WeeklyReviewJob`** — hardcoded user, `Notion::TrainingWeek.today`, call generator, log failures.

- [ ] **Step 1: Write failing generator tests** — cover: (a) creates row with computed aggregates + parsed LLM fields when none exists; (b) updates (not creates) when a row for `Week Start` exists; (c) red-flag name mapping incl. `Sleep short` and `Multiple red flags`; (d) malformed LLM JSON → `Cautious` fallback, still writes aggregates; (e) `Long Run Distance` only considers Done+Long rows. Use `FakeNotionClient` query_results sequencing (weekly query, workouts query, daily logs query).
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement generator + job.** Run tests → PASS.
- [ ] **Step 4: Add commented recurring entry:**

```yaml
  # weekly_review:
  #   class: WeeklyReviewJob
  #   schedule: "22 21 * * 0 America/Los_Angeles"   # Sundays 9:22pm PT
```

- [ ] **Step 5: Full suite + linter** — `bin/rails test` and `bundle exec standardrb` → green.
- [ ] **Step 6: Commit** — `git commit -m "feat: add weekly review generation"`

---

### Task 11: End-to-end verification + staged rollout

**Files:**
- Modify: `config/recurring.yml` (uncomment entries, staged)
- Modify: `.env` / Render env vars (Task 0 of this section)

- [ ] **Step 1: Set env vars.** Add the four non-secret vars (data source IDs + `TRAINING_WEEK1_START`) to local `.env` and the Render dashboard. **Ask Jules to confirm `TRAINING_WEEK1_START=2026-05-04`** (derived from "Thu Jun 11 (W6 D4)": W6 starts Mon Jun 8, so W1 starts Mon May 4).

- [ ] **Step 2: Refresh local DB from production** — `bin/rails db:pull` (existing task) so the one-shot uses real data.

- [ ] **Step 3: One-shot data sync against real Notion** (data fields only — no LLM):

```bash
bash -c 'set -a; . .env; set +a; bin/rails runner "NotionSyncJob.perform_now"'
```
Expected: today's (and yesterday's) Daily Logs rows update with weight/sleep/HRV/RHR/calories; any of today's workouts get actuals + Done. **Verify by eye in Notion.** Check: no human fields changed, no duplicate rows, titles untouched on existing pages.

- [ ] **Step 4: One-shot commentary + weekly review dry-run** (requires `LLM_MODEL` + provider key envs — same as production):

```bash
bash -c 'set -a; . .env; set +a; bin/rails runner "DailyLogCommentaryJob.perform_now"'
bash -c 'set -a; . .env; set +a; bin/rails runner "WeeklyReviewJob.perform_now"'
```
Verify in Notion: Notes narrative reads sensibly; red flags merged not replaced; weekly row upserted (run twice — second run must update, not duplicate).

- [ ] **Step 5: Deploy with `notion_catchup` enabled** — uncomment only `notion_catchup` in `config/recurring.yml`, commit, push, deploy. Webhook chaining is already live from Task 7 (it's harmless alongside catchup thanks to `limits_concurrency`).

- [ ] **Step 6: After one clean day** — uncomment `daily_log_commentary` and `weekly_review`, commit, push, deploy.

- [ ] **Step 7: Monitor** — check `solid_queue_failed_executions` after the first evening run:

```bash
bash -c 'set -a; . .env; set +a; bin/rails runner "puts SolidQueue::FailedExecution.count"'
```
(against production: use the Render shell or `DATABASE_URL` override, matching how `db:pull` connects).

- [ ] **Step 8: Final commit + update spec status** — mark rollout complete in the spec doc header.

---

## Out of scope (per spec)

- MCP server / read API for Claude iOS chats
- Multi-user support
- Backfilling historical Notion pages
