# Phase 1, Slice 2: Health Data Pipeline — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Ingest HealthKit data from Health Auto Export into Postgres via a webhook, with a dashboard proving data flows end-to-end.

**Architecture:** Bearer-token-authenticated webhook endpoint receives JSON from Health Auto Export. A service object (`HealthDataProcessor`) orchestrates parsing via `MetricsParser` and `WorkoutParser`, storing results in three new tables. The existing dashboard is replaced with cards showing real data.

**Tech Stack:** Rails 8.1, PostgreSQL (JSONB), Minitest, Tailwind CSS

**Design doc:** `docs/plans/2026-03-15-phase1-slice2-design.md`

---

### Task 1: Database migrations

**Files:**
- Create: `db/migrate/XXXXXX_create_health_payloads.rb`
- Create: `db/migrate/XXXXXX_create_health_metrics.rb`
- Create: `db/migrate/XXXXXX_create_workouts.rb`

**Step 1: Generate the three migrations**

Run:
```bash
bin/rails generate model HealthPayload raw_json:jsonb status:string error_message:text --no-fixture
bin/rails generate model HealthMetric metric_name:string recorded_at:datetime value:decimal units:string metadata:jsonb --no-fixture
bin/rails generate model Workout external_id:string workout_type:string started_at:datetime ended_at:datetime duration:integer distance:decimal distance_units:string energy_burned:decimal metadata:jsonb --no-fixture
```

**Step 2: Edit the migrations**

Add defaults and constraints to each migration:

`create_health_payloads`:
```ruby
t.jsonb :raw_json, null: false
t.string :status, null: false, default: "pending"
t.text :error_message
```

`create_health_metrics`:
```ruby
t.string :metric_name, null: false
t.datetime :recorded_at, null: false
t.decimal :value, null: false
t.string :units, null: false
t.jsonb :metadata
t.index [:metric_name, :recorded_at], unique: true
```

`create_workouts`:
```ruby
t.string :external_id, null: false
t.string :workout_type, null: false
t.datetime :started_at, null: false
t.datetime :ended_at, null: false
t.integer :duration, null: false
t.decimal :distance
t.string :distance_units
t.decimal :energy_burned
t.jsonb :metadata
t.index [:external_id], unique: true
```

**Step 3: Run migrations**

Run: `bin/rails db:migrate`
Expected: Schema updated, three new tables created.

**Step 4: Commit**

```bash
git add db/ app/models/health_payload.rb app/models/health_metric.rb app/models/workout.rb
git commit -m "feat: add health_payloads, health_metrics, and workouts tables"
```

---

### Task 2: Models with validations

**Files:**
- Modify: `app/models/health_payload.rb`
- Modify: `app/models/health_metric.rb`
- Modify: `app/models/workout.rb`
- Create: `test/models/health_payload_test.rb`
- Create: `test/models/health_metric_test.rb`
- Create: `test/models/workout_test.rb`

**Step 1: Write failing model tests**

`test/models/health_payload_test.rb`:
```ruby
require "test_helper"

class HealthPayloadTest < ActiveSupport::TestCase
  test "valid with raw_json and status" do
    payload = HealthPayload.new(raw_json: {data: {}}, status: "pending")
    assert payload.valid?
  end

  test "invalid without raw_json" do
    payload = HealthPayload.new(raw_json: nil, status: "pending")
    assert_not payload.valid?
  end

  test "invalid with unknown status" do
    payload = HealthPayload.new(raw_json: {data: {}}, status: "unknown")
    assert_not payload.valid?
  end
end
```

`test/models/health_metric_test.rb`:
```ruby
require "test_helper"

class HealthMetricTest < ActiveSupport::TestCase
  test "valid with all required fields" do
    metric = HealthMetric.new(
      metric_name: "weight", recorded_at: Time.current,
      value: 82.5, units: "kg"
    )
    assert metric.valid?
  end

  test "invalid without metric_name" do
    metric = HealthMetric.new(recorded_at: Time.current, value: 82.5, units: "kg")
    assert_not metric.valid?
  end

  test "enforces uniqueness on metric_name and recorded_at" do
    time = Time.current
    HealthMetric.create!(metric_name: "weight", recorded_at: time, value: 82.5, units: "kg")
    duplicate = HealthMetric.new(metric_name: "weight", recorded_at: time, value: 83.0, units: "kg")
    assert_not duplicate.valid?
  end
end
```

`test/models/workout_test.rb`:
```ruby
require "test_helper"

class WorkoutTest < ActiveSupport::TestCase
  test "valid with all required fields" do
    workout = Workout.new(
      external_id: "ABC-123", workout_type: "Running",
      started_at: 1.hour.ago, ended_at: Time.current,
      duration: 3600
    )
    assert workout.valid?
  end

  test "invalid without external_id" do
    workout = Workout.new(workout_type: "Running", started_at: 1.hour.ago, ended_at: Time.current, duration: 3600)
    assert_not workout.valid?
  end

  test "enforces uniqueness on external_id" do
    Workout.create!(external_id: "ABC-123", workout_type: "Running", started_at: 1.hour.ago, ended_at: Time.current, duration: 3600)
    duplicate = Workout.new(external_id: "ABC-123", workout_type: "Running", started_at: 1.hour.ago, ended_at: Time.current, duration: 3600)
    assert_not duplicate.valid?
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/health_payload_test.rb test/models/health_metric_test.rb test/models/workout_test.rb`
Expected: Failures (validation not yet added).

**Step 3: Add validations to models**

`app/models/health_payload.rb`:
```ruby
class HealthPayload < ApplicationRecord
  validates :raw_json, presence: true
  validates :status, presence: true, inclusion: {in: %w[pending processed failed]}
end
```

`app/models/health_metric.rb`:
```ruby
class HealthMetric < ApplicationRecord
  validates :metric_name, presence: true
  validates :recorded_at, presence: true
  validates :value, presence: true
  validates :units, presence: true
  validates :metric_name, uniqueness: {scope: :recorded_at}
end
```

`app/models/workout.rb`:
```ruby
class Workout < ApplicationRecord
  validates :external_id, presence: true, uniqueness: true
  validates :workout_type, presence: true
  validates :started_at, presence: true
  validates :ended_at, presence: true
  validates :duration, presence: true
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/health_payload_test.rb test/models/health_metric_test.rb test/models/workout_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/models/ test/models/
git commit -m "feat: add validations for health data models"
```

---

### Task 3: MetricsParser service

**Files:**
- Create: `app/services/metrics_parser.rb`
- Create: `test/services/metrics_parser_test.rb`

**Step 1: Write failing tests**

`test/services/metrics_parser_test.rb`:
```ruby
require "test_helper"

class MetricsParserTest < ActiveSupport::TestCase
  setup do
    payload_json = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @metrics_data = payload_json.dig("data", "metrics")
  end

  test "parses simple qty metrics (weight)" do
    weight_data = @metrics_data.find { |m| m["name"] == "weight" }
    result = MetricsParser.call([weight_data])

    assert_equal 1, result.created
    metric = HealthMetric.find_by(metric_name: "weight")
    assert_equal 82.5, metric.value
    assert_equal "kg", metric.units
  end

  test "parses sleep_analysis with metadata" do
    sleep_data = @metrics_data.find { |m| m["name"] == "sleep_analysis" }
    result = MetricsParser.call([sleep_data])

    metric = HealthMetric.find_by(metric_name: "sleep_analysis")
    assert_equal 7.2, metric.value
    assert_equal "hr", metric.units
    assert_equal 1.8, metric.metadata["deep"]
    assert_equal 1.5, metric.metadata["rem"]
  end

  test "parses heart_rate with min/avg/max metadata" do
    hr_data = @metrics_data.find { |m| m["name"] == "heart_rate" }
    result = MetricsParser.call([hr_data])

    assert_equal 3, result.created
    metric = HealthMetric.where(metric_name: "heart_rate").order(:recorded_at).first
    assert_equal 58, metric.value
    assert_equal({"min" => 55, "avg" => 58, "max" => 62}, metric.metadata)
  end

  test "deduplicates on metric_name and recorded_at" do
    weight_data = @metrics_data.find { |m| m["name"] == "weight" }
    MetricsParser.call([weight_data])
    result = MetricsParser.call([weight_data])

    assert_equal 0, result.created
    assert_equal 1, result.skipped
    assert_equal 1, HealthMetric.where(metric_name: "weight").count
  end

  test "parses all metrics from example payload" do
    result = MetricsParser.call(@metrics_data)

    assert result.created > 0
    assert_equal 0, result.skipped
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/metrics_parser_test.rb`
Expected: FAIL — `MetricsParser` not defined.

**Step 3: Implement MetricsParser**

`app/services/metrics_parser.rb`:
```ruby
class MetricsParser
  Result = Struct.new(:created, :skipped, keyword_init: true)

  SLEEP_VALUE_KEY = "totalSleep"
  HR_VALUE_KEY = "Avg"
  SIMPLE_VALUE_KEY = "qty"

  def self.call(metrics_data)
    new(metrics_data).call
  end

  def initialize(metrics_data)
    @metrics_data = metrics_data
  end

  def call
    created = 0
    skipped = 0

    @metrics_data.each do |metric_entry|
      name = metric_entry["name"]
      units = metric_entry["units"]

      metric_entry["data"].each do |data_point|
        recorded_at = parse_timestamp(data_point["date"])
        value = extract_value(name, data_point)
        metadata = extract_metadata(name, data_point)

        existing = HealthMetric.find_by(metric_name: name, recorded_at: recorded_at)
        if existing
          skipped += 1
        else
          HealthMetric.create!(
            metric_name: name,
            recorded_at: recorded_at,
            value: value,
            units: units,
            metadata: metadata
          )
          created += 1
        end
      end
    end

    Result.new(created: created, skipped: skipped)
  end

  private

  def extract_value(name, data_point)
    case name
    when "sleep_analysis"
      data_point[SLEEP_VALUE_KEY]
    when "heart_rate"
      data_point[HR_VALUE_KEY]
    else
      data_point[SIMPLE_VALUE_KEY]
    end
  end

  def extract_metadata(name, data_point)
    case name
    when "sleep_analysis"
      data_point.except("date", SLEEP_VALUE_KEY)
    when "heart_rate"
      {"min" => data_point["Min"], "avg" => data_point["Avg"], "max" => data_point["Max"]}
    else
      nil
    end
  end

  def parse_timestamp(date_string)
    Time.parse(date_string)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/metrics_parser_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/services/metrics_parser.rb test/services/metrics_parser_test.rb
git commit -m "feat: add MetricsParser service for health metric ingestion"
```

---

### Task 4: WorkoutParser service

**Files:**
- Create: `app/services/workout_parser.rb`
- Create: `test/services/workout_parser_test.rb`

**Step 1: Write failing tests**

`test/services/workout_parser_test.rb`:
```ruby
require "test_helper"

class WorkoutParserTest < ActiveSupport::TestCase
  setup do
    payload_json = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @workouts_data = payload_json.dig("data", "workouts")
  end

  test "parses a running workout with common fields" do
    result = WorkoutParser.call(@workouts_data)

    assert_equal 1, result.created
    workout = Workout.find_by(external_id: "F4A3B2C1-1234-5678-9ABC-DEF012345678")
    assert_equal "Running", workout.workout_type
    assert_equal 2700, workout.duration
    assert_in_delta 8.04, workout.distance
    assert_equal "km", workout.distance_units
    assert_in_delta 485.3, workout.energy_burned
  end

  test "stores time-series and route data in metadata" do
    WorkoutParser.call(@workouts_data)
    workout = Workout.first

    assert workout.metadata["heartRateData"].is_a?(Array)
    assert workout.metadata["route"].is_a?(Array)
    assert_equal 9, workout.metadata["heartRateData"].length
    assert_equal 3, workout.metadata["route"].length
  end

  test "stores heart rate summary in metadata" do
    WorkoutParser.call(@workouts_data)
    workout = Workout.first

    assert_equal 155, workout.metadata.dig("heartRate", "avg")
    assert_equal 178, workout.metadata.dig("heartRate", "max")
    assert_equal 98, workout.metadata.dig("heartRate", "min")
  end

  test "deduplicates on external_id" do
    WorkoutParser.call(@workouts_data)
    result = WorkoutParser.call(@workouts_data)

    assert_equal 0, result.created
    assert_equal 1, result.skipped
    assert_equal 1, Workout.count
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/workout_parser_test.rb`
Expected: FAIL — `WorkoutParser` not defined.

**Step 3: Implement WorkoutParser**

`app/services/workout_parser.rb`:
```ruby
class WorkoutParser
  Result = Struct.new(:created, :skipped, keyword_init: true)

  COMMON_FIELDS = %w[id name start end duration location isIndoor].freeze

  def self.call(workouts_data)
    new(workouts_data).call
  end

  def initialize(workouts_data)
    @workouts_data = workouts_data
  end

  def call
    created = 0
    skipped = 0

    @workouts_data.each do |workout_data|
      external_id = workout_data["id"]

      if Workout.exists?(external_id: external_id)
        skipped += 1
      else
        Workout.create!(
          external_id: external_id,
          workout_type: workout_data["name"],
          started_at: Time.parse(workout_data["start"]),
          ended_at: Time.parse(workout_data["end"]),
          duration: workout_data["duration"],
          distance: workout_data.dig("distance", "qty"),
          distance_units: workout_data.dig("distance", "units"),
          energy_burned: workout_data.dig("activeEnergyBurned", "qty"),
          metadata: build_metadata(workout_data)
        )
        created += 1
      end
    end

    Result.new(created: created, skipped: skipped)
  end

  private

  def build_metadata(workout_data)
    metadata = workout_data.except(*COMMON_FIELDS)

    # Flatten {qty, units} fields to just values for common ones already in columns
    metadata.delete("distance")
    metadata.delete("activeEnergyBurned")

    # Normalize heart rate summary
    if (hr = metadata.delete("heartRate"))
      metadata["heartRate"] = {
        "min" => hr.dig("min", "qty"),
        "avg" => hr.dig("avg", "qty"),
        "max" => hr.dig("max", "qty")
      }
    end

    metadata
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/workout_parser_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/services/workout_parser.rb test/services/workout_parser_test.rb
git commit -m "feat: add WorkoutParser service for workout ingestion"
```

---

### Task 5: HealthDataProcessor service

**Files:**
- Create: `app/services/health_data_processor.rb`
- Create: `test/services/health_data_processor_test.rb`

**Step 1: Write failing tests**

`test/services/health_data_processor_test.rb`:
```ruby
require "test_helper"

class HealthDataProcessorTest < ActiveSupport::TestCase
  setup do
    raw_json = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @payload = HealthPayload.create!(raw_json: raw_json, status: "pending")
  end

  test "processes a valid payload end-to-end" do
    result = HealthDataProcessor.call(@payload)

    assert result.success?
    assert result.metrics_created > 0
    assert result.workouts_created > 0
    assert_equal "processed", @payload.reload.status
  end

  test "marks payload as failed on error" do
    @payload.update!(raw_json: {"data" => {"metrics" => "not_an_array"}})
    result = HealthDataProcessor.call(@payload)

    assert_not result.success?
    assert_equal "failed", @payload.reload.status
    assert @payload.error_message.present?
  end

  test "rolls back all records on partial failure" do
    @payload.update!(raw_json: {"data" => {"metrics" => [], "workouts" => "bad"}})
    HealthDataProcessor.call(@payload)

    assert_equal 0, HealthMetric.count
    assert_equal 0, Workout.count
  end

  test "handles payload with only metrics (no workouts key)" do
    @payload.update!(raw_json: {"data" => {"metrics" => @payload.raw_json.dig("data", "metrics")}})
    result = HealthDataProcessor.call(@payload)

    assert result.success?
    assert result.metrics_created > 0
    assert_equal 0, result.workouts_created
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/health_data_processor_test.rb`
Expected: FAIL — `HealthDataProcessor` not defined.

**Step 3: Implement HealthDataProcessor**

`app/services/health_data_processor.rb`:
```ruby
class HealthDataProcessor
  Result = Struct.new(:success?, :metrics_created, :metrics_skipped, :workouts_created, :workouts_skipped, keyword_init: true)

  def self.call(health_payload)
    new(health_payload).call
  end

  def initialize(health_payload)
    @health_payload = health_payload
  end

  def call
    data = @health_payload.raw_json["data"]
    metrics_result = nil
    workouts_result = nil

    ActiveRecord::Base.transaction do
      metrics_data = data["metrics"] || []
      workouts_data = data["workouts"] || []

      metrics_result = MetricsParser.call(metrics_data)
      workouts_result = WorkoutParser.call(workouts_data)
    end

    @health_payload.update!(status: "processed")

    Result.new(
      "success?": true,
      metrics_created: metrics_result.created,
      metrics_skipped: metrics_result.skipped,
      workouts_created: workouts_result.created,
      workouts_skipped: workouts_result.skipped
    )
  rescue => e
    @health_payload.update!(status: "failed", error_message: "#{e.class}: #{e.message}")
    Result.new(
      "success?": false,
      metrics_created: 0,
      metrics_skipped: 0,
      workouts_created: 0,
      workouts_skipped: 0
    )
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/health_data_processor_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/services/health_data_processor.rb test/services/health_data_processor_test.rb
git commit -m "feat: add HealthDataProcessor orchestrator service"
```

---

### Task 6: Webhook controller

**Files:**
- Create: `app/controllers/api/v1/health_data_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/v1/health_data_controller_test.rb`

**Step 1: Write failing tests**

`test/controllers/api/v1/health_data_controller_test.rb`:
```ruby
require "test_helper"

class Api::V1::HealthDataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @payload = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @token = "test-webhook-token"
    ENV["WEBHOOK_AUTH_TOKEN"] = @token
  end

  test "returns 401 without authorization header" do
    post api_v1_health_data_path, params: @payload, as: :json
    assert_response :unauthorized
  end

  test "returns 401 with wrong token" do
    post api_v1_health_data_path,
      params: @payload,
      headers: {"Authorization" => "Bearer wrong-token"},
      as: :json
    assert_response :unauthorized
  end

  test "returns 200 and processes valid payload" do
    post api_v1_health_data_path,
      params: @payload,
      headers: {"Authorization" => "Bearer #{@token}"},
      as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
    assert json["metrics_count"] > 0
    assert json["workouts_count"] > 0
  end

  test "creates a health_payload record" do
    assert_difference "HealthPayload.count", 1 do
      post api_v1_health_data_path,
        params: @payload,
        headers: {"Authorization" => "Bearer #{@token}"},
        as: :json
    end

    assert_equal "processed", HealthPayload.last.status
  end

  test "returns 422 on malformed payload" do
    post api_v1_health_data_path,
      params: {data: {metrics: "bad"}},
      headers: {"Authorization" => "Bearer #{@token}"},
      as: :json

    assert_response :unprocessable_entity
    assert_equal "failed", HealthPayload.last.status
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/api/v1/health_data_controller_test.rb`
Expected: FAIL — route and controller not defined.

**Step 3: Add route**

Update `config/routes.rb` — add the API namespace before the root route:
```ruby
namespace :api do
  namespace :v1 do
    resource :health_data, only: [:create], controller: "health_data"
  end
end
```

**Step 4: Create controller**

`app/controllers/api/v1/health_data_controller.rb`:
```ruby
class Api::V1::HealthDataController < ActionController::API
  before_action :authenticate_token!

  def create
    health_payload = HealthPayload.create!(
      raw_json: params.permit!.to_h,
      status: "pending"
    )

    result = HealthDataProcessor.call(health_payload)

    if result.success?
      render json: {
        status: "ok",
        metrics_count: result.metrics_created,
        workouts_count: result.workouts_created
      }
    else
      render json: {
        status: "error",
        error: health_payload.reload.error_message
      }, status: :unprocessable_entity
    end
  end

  private

  def authenticate_token!
    token = request.headers["Authorization"]&.split("Bearer ")&.last
    head :unauthorized unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, ENV.fetch("WEBHOOK_AUTH_TOKEN"))
  end
end
```

Note: Inherits from `ActionController::API` (not `ApplicationController`) to skip Devise auth and `allow_browser`.

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/api/v1/health_data_controller_test.rb`
Expected: All pass.

**Step 6: Commit**

```bash
git add app/controllers/api/ test/controllers/api/ config/routes.rb
git commit -m "feat: add webhook endpoint for Health Auto Export data"
```

---

### Task 7: Dashboard

**Files:**
- Modify: `app/controllers/dashboard_controller.rb`
- Modify: `app/views/dashboard/index.html.erb`
- Create: `test/integration/dashboard_test.rb`

**Step 1: Write failing integration test**

`test/integration/dashboard_test.rb`:
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
    Workout.create!(
      external_id: "ABC-123", workout_type: "Running",
      started_at: 2.hours.ago, ended_at: 1.hour.ago, duration: 3600,
      distance: 10.0, distance_units: "km", energy_burned: 600
    )
    HealthPayload.create!(raw_json: {data: {}}, status: "processed")
  end

  test "dashboard shows latest metrics" do
    get root_path
    assert_response :success
    assert_select "text", /82\.5/  # weight
  end

  test "dashboard shows sleep data" do
    get root_path
    assert_select "text", /7\.2/  # total sleep
  end

  test "dashboard shows recent workouts" do
    get root_path
    assert_select "text", /Running/
  end

  test "dashboard shows pipeline status" do
    get root_path
    assert_select "text", /1 payload/i
  end
end
```

Note: The `assert_select "text"` calls should be adjusted during implementation to match the actual markup. These tests verify the data appears on the page — the specific selectors will be refined when writing the view.

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/dashboard_test.rb`
Expected: FAIL — no data displayed on dashboard.

**Step 3: Update dashboard controller**

`app/controllers/dashboard_controller.rb`:
```ruby
class DashboardController < ApplicationController
  METRIC_TYPES = %w[weight body_fat_percentage vo2_max resting_heart_rate heart_rate_variability step_count active_energy].freeze

  def index
    @latest_metrics = METRIC_TYPES.filter_map do |name|
      HealthMetric.where(metric_name: name).order(recorded_at: :desc).first
    end
    @latest_sleep = HealthMetric.where(metric_name: "sleep_analysis").order(recorded_at: :desc).first
    @recent_workouts = Workout.order(started_at: :desc).limit(5)
    @pipeline_stats = {
      total_payloads: HealthPayload.count,
      last_received: HealthPayload.order(created_at: :desc).first&.created_at,
      failed_count: HealthPayload.where(status: "failed").count
    }
  end
end
```

**Step 4: Replace dashboard view**

Replace `app/views/dashboard/index.html.erb` with the full dashboard layout. Four sections:

1. **Header** — "Signals" title with last sync time
2. **Latest Metrics** — responsive grid of stat cards
3. **Sleep** — card with total sleep, in-bed times, and core/deep/REM bar
4. **Recent Workouts** — table of last 5 workouts
5. **Pipeline Status** — small status bar at bottom

Use Tailwind utilities throughout. No custom CSS. The view will use standard ERB — no partials needed at this stage (only one page uses these components).

**Step 5: Adjust test selectors to match actual markup, run tests**

Run: `bin/rails test test/integration/dashboard_test.rb`
Expected: All pass.

**Step 6: Commit**

```bash
git add app/controllers/dashboard_controller.rb app/views/dashboard/index.html.erb test/integration/dashboard_test.rb
git commit -m "feat: add health data dashboard with metrics, sleep, workouts, and pipeline status"
```

---

### Task 8: Update docs and architecture

**Files:**
- Modify: `docs/architecture.md` — update database tables section from "Phase 1 (next slice)" to "Current"
- Modify: `docs/deployment.md` — add `WEBHOOK_AUTH_TOKEN` env var
- Modify: `AGENTS.md` — update "What's next" section

**Step 1: Update docs**

`docs/architecture.md`: Change "Phase 1 (next slice)" to "Current" for the three health data tables. Add `app/services/` to the architecture description.

`AGENTS.md`: Update "What's next" to reflect that Slice 2 is complete and the next step is configuring Health Auto Export and verifying real data flow, then Phase 2.

**Step 2: Commit**

```bash
git add docs/architecture.md docs/deployment.md AGENTS.md
git commit -m "docs: update architecture and deployment for Phase 1 Slice 2"
```

---

### Task 9: Run full test suite and verify

**Step 1: Run all tests**

Run: `bin/rails test`
Expected: All tests pass.

**Step 2: Run linters**

Run: `bundle exec standardrb`
Expected: No offenses.

Run: `bin/brakeman`
Expected: No warnings.

**Step 3: Manual smoke test (optional)**

Start the server locally and POST the example payload:
```bash
bin/rails server &
curl -X POST http://localhost:3000/api/v1/health_data \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $WEBHOOK_AUTH_TOKEN" \
  -d @docs/example_workout_payload.json
```
Expected: `{"status":"ok","metrics_count":...,"workouts_count":...}`

Visit `http://localhost:3000` — should see the dashboard with real data.
