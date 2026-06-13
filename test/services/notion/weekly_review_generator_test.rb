require "test_helper"
require_relative "fake_notion_client"
require_relative "../../support/llm_stubbing"

class Notion::WeeklyReviewGeneratorTest < ActiveSupport::TestCase
  include LlmStubbing

  # A Thursday in W6 (week start Mon Jun 8, week end Sun Jun 14)
  DATE = Date.new(2026, 6, 12)
  WEEK_START = Date.new(2026, 6, 8)
  WEEK_END = Date.new(2026, 6, 14)

  setup do
    @orig_llm_model = ENV["LLM_MODEL"]
    @orig_notion_api_token = ENV["NOTION_API_TOKEN"]
    @orig_training_week1_start = ENV["TRAINING_WEEK1_START"]
    @orig_notion_weekly_reviews_ds_id = ENV["NOTION_WEEKLY_REVIEWS_DS_ID"]
    @orig_notion_workouts_ds_id = ENV["NOTION_WORKOUTS_DS_ID"]
    @orig_notion_daily_logs_ds_id = ENV["NOTION_DAILY_LOGS_DS_ID"]

    ENV["LLM_MODEL"] = "gpt-5-nano"
    ENV["NOTION_API_TOKEN"] = "test-token"
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_WEEKLY_REVIEWS_DS_ID"] = "ds-weekly"
    ENV["NOTION_WORKOUTS_DS_ID"] = "ds-workouts"
    ENV["NOTION_DAILY_LOGS_DS_ID"] = "ds-daily"

    @user = users(:one)
    @fake_llm_response = Data.define(:content).new(
      content: '{"status":"On Track","what_worked":"Good mileage.","what_broke":"Nothing.","adjustment_for_next_week":"Keep it up."}'
    )
  end

  teardown do
    ENV["LLM_MODEL"] = @orig_llm_model
    ENV["NOTION_API_TOKEN"] = @orig_notion_api_token
    ENV["TRAINING_WEEK1_START"] = @orig_training_week1_start
    ENV["NOTION_WEEKLY_REVIEWS_DS_ID"] = @orig_notion_weekly_reviews_ds_id
    ENV["NOTION_WORKOUTS_DS_ID"] = @orig_notion_workouts_ds_id
    ENV["NOTION_DAILY_LOGS_DS_ID"] = @orig_notion_daily_logs_ds_id
  end

  def workout_row(status:, type:, planned_km: nil, actual_km: nil)
    props = {
      "Status" => {"select" => {"name" => status}},
      "Type" => {"select" => {"name" => type}},
      "Planned Distance (km)" => {"number" => planned_km},
      "Actual Distance (km)" => {"number" => actual_km}
    }
    {"id" => "workout-#{SecureRandom.hex(4)}", "properties" => props}
  end

  def daily_log_row(red_flags: [])
    flag_data = red_flags.map { |f| {"name" => f} }
    {
      "id" => "daily-#{SecureRandom.hex(4)}",
      "properties" => {"Red Flags" => {"multi_select" => flag_data}}
    }
  end

  def seed_metrics(date, hrv: nil, rhr: nil, sleep: nil, weight: nil)
    tz = ActiveSupport::TimeZone["America/Los_Angeles"]
    noon = tz.local(date.year, date.month, date.day, 12)
    @user.health_metrics.create!(metric_name: "heart_rate_variability", value: hrv, units: "ms", recorded_at: noon) if hrv
    @user.health_metrics.create!(metric_name: "resting_heart_rate", value: rhr, units: "bpm", recorded_at: noon) if rhr
    @user.health_metrics.create!(metric_name: "sleep_analysis", value: sleep, units: "h", recorded_at: noon) if sleep
    @user.health_metrics.create!(metric_name: "weight", value: weight, units: "kg", recorded_at: noon) if weight
  end

  # (a) creates row with computed aggregates + parsed LLM fields when none exists
  test "creates row with computed aggregates and parsed LLM fields when none exists" do
    seed_metrics(WEEK_START, hrv: 55.0, rhr: 48.0, sleep: 7.5, weight: 61.0)
    seed_metrics(WEEK_START + 1, hrv: 60.0, rhr: 50.0, sleep: 8.0, weight: 61.2)

    workouts_rows = [
      workout_row(status: "Done", type: "Easy", planned_km: 5.0, actual_km: 5.1),
      workout_row(status: "Done", type: "Long", planned_km: 12.0, actual_km: 11.8),
      workout_row(status: "Planned", type: "Quality", planned_km: 8.0, actual_km: nil)
    ]
    daily_logs_rows = [daily_log_row(red_flags: ["RHR up"])]

    # Query sequence: weekly-review query (empty), workouts query, daily-logs query
    client = FakeNotionClient.new(query_results: [[], workouts_rows, daily_logs_rows])

    stub_llm_chat(@fake_llm_response) do
      result = Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)

      assert result.success
      assert result.created
      assert_equal 3, client.queries.size
      assert_equal 1, client.creates.size
      assert_empty client.updates

      props = client.creates.first[:properties]

      # LLM parsed fields
      assert_equal "On Track", props["Status"]["select"]["name"]
      assert_equal "Good mileage.", props["What Worked"]["rich_text"].first["text"]["content"]
      assert_equal "Nothing.", props["What Broke"]["rich_text"].first["text"]["content"]
      assert_equal "Keep it up.", props["Adjustment for Next Week"]["rich_text"].first["text"]["content"]

      # Aggregates
      assert_in_delta 25.0, props["Planned km"]["number"], 0.01  # 5+12+8
      assert_in_delta 16.9, props["Actual km"]["number"], 0.1    # 5.1+11.8 (done rows)
      assert_in_delta 11.8, props["Long Run Distance (km)"]["number"], 0.01
      refute props["Quality Session Done"]["checkbox"]  # Quality is Planned, not Done
      refute props["Strength Done"]["checkbox"]

      # DB aggregates
      assert_in_delta 57.5, props["Avg HRV"]["number"], 0.5    # (55+60)/2
      assert_in_delta 49.0, props["Avg RHR"]["number"], 0.5    # (48+50)/2
      assert_in_delta 7.75, props["Avg Sleep Hours"]["number"], 0.1
      assert_in_delta 61.0, props["Weight Start (kg)"]["number"], 0.01
      assert_in_delta 61.2, props["Weight End (kg)"]["number"], 0.01

      # Red flags
      flag_names = props["Red Flags Triggered"]["multi_select"].map { |f| f["name"] }
      assert_includes flag_names, "RHR up"

      # Create-only properties
      assert_match(/W6/, props["Week"]["title"].first["text"]["content"])
      assert_equal 6, props["Week Number"]["number"]
      assert_equal WEEK_START.iso8601, props["Week Start"]["date"]["start"]
    end
  end

  # (b) updates (not creates) when a row for Week Start exists
  test "updates existing row and does not create a duplicate" do
    existing = {
      "id" => "weekly-existing-1",
      "properties" => {
        "Red Flags Triggered" => {"multi_select" => []}
      }
    }
    workouts_rows = [workout_row(status: "Done", type: "Easy", planned_km: 5.0, actual_km: 5.0)]
    daily_logs_rows = []

    client = FakeNotionClient.new(query_results: [[existing], workouts_rows, daily_logs_rows])

    stub_llm_chat(@fake_llm_response) do
      result = Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)

      assert result.success
      refute result.created
      assert_empty client.creates
      assert_equal 1, client.updates.size
      assert_equal "weekly-existing-1", client.updates.first[:page_id]

      # Update should NOT include create-only properties
      props = client.updates.first[:properties]
      refute props.key?("Week")
      refute props.key?("Week Number")
      refute props.key?("Week Start")
    end
  end

  # (c) red-flag mapping: "Sleep <6.5h" → "Sleep short" and "Multiple red flags" at ≥3
  test "maps Sleep <6.5h to Sleep short and adds Multiple red flags at 3+ distinct flags" do
    daily_logs_rows = [
      daily_log_row(red_flags: ["Sleep <6.5h", "RHR up"]),
      daily_log_row(red_flags: ["HRV down", "Weight loss too fast"])
    ]

    # 4 distinct mapped flags → Multiple red flags added
    client = FakeNotionClient.new(query_results: [[], [], daily_logs_rows])

    stub_llm_chat(@fake_llm_response) do
      result = Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)

      assert result.success
      props = client.creates.first[:properties]
      flag_names = props["Red Flags Triggered"]["multi_select"].map { |f| f["name"] }

      assert_includes flag_names, "Sleep short"       # mapped from "Sleep <6.5h"
      refute_includes flag_names, "Sleep <6.5h"       # original name dropped
      assert_includes flag_names, "RHR up"
      assert_includes flag_names, "HRV down"
      assert_includes flag_names, "Weight loss too fast"
      assert_includes flag_names, "Multiple red flags"
    end
  end

  test "does not add Multiple red flags when fewer than 3 distinct flags" do
    daily_logs_rows = [daily_log_row(red_flags: ["Sleep <6.5h", "RHR up"])]

    client = FakeNotionClient.new(query_results: [[], [], daily_logs_rows])

    stub_llm_chat(@fake_llm_response) do
      result = Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)

      assert result.success
      props = client.creates.first[:properties]
      flag_names = props["Red Flags Triggered"]["multi_select"].map { |f| f["name"] }

      assert_includes flag_names, "Sleep short"
      refute_includes flag_names, "Multiple red flags"
    end
  end

  # (d) malformed LLM JSON → "Cautious" fallback, aggregates still written
  test "malformed LLM JSON falls back to Cautious status with raw text in What Worked" do
    raw_bad_response = Data.define(:content).new(content: "Sorry, I cannot do that right now.")

    workouts_rows = [workout_row(status: "Done", type: "Easy", planned_km: 5.0, actual_km: 5.0)]
    client = FakeNotionClient.new(query_results: [[], workouts_rows, []])

    stub_llm_chat(raw_bad_response) do
      result = Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)

      assert result.success
      props = client.creates.first[:properties]

      assert_equal "Cautious", props["Status"]["select"]["name"]
      what_worked_text = props["What Worked"]["rich_text"].first["text"]["content"]
      assert_match "Sorry, I cannot do that right now.", what_worked_text

      # Aggregates still written
      assert props.key?("Actual km")
      assert props.key?("Planned km")
    end
  end

  # (e) Long Run Distance only considers Done+Long rows
  test "Long Run Distance only considers Done rows with Type Long" do
    workouts_rows = [
      workout_row(status: "Done", type: "Long", planned_km: 12.0, actual_km: 15.0),
      workout_row(status: "Planned", type: "Long", planned_km: 18.0, actual_km: 18.0), # Planned — must be ignored
      workout_row(status: "Done", type: "Easy", planned_km: 5.0, actual_km: 5.0)        # Easy — must be ignored
    ]

    client = FakeNotionClient.new(query_results: [[], workouts_rows, []])

    stub_llm_chat(@fake_llm_response) do
      result = Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)

      assert result.success
      props = client.creates.first[:properties]
      assert_in_delta 15.0, props["Long Run Distance (km)"]["number"], 0.01
    end
  end

  test "omits nil aggregates from properties" do
    # No health metrics → no HRV/RHR/sleep/weight aggregates
    client = FakeNotionClient.new(query_results: [[], [], []])

    stub_llm_chat(@fake_llm_response) do
      Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)
    end

    props = client.creates.first[:properties]
    refute props.key?("Avg HRV")
    refute props.key?("Avg RHR")
    refute props.key?("Avg Sleep Hours")
    refute props.key?("Weight Start (kg)")
    refute props.key?("Weight End (kg)")
    refute props.key?("Planned km")
    refute props.key?("Actual km")
  end

  test "returns failure result on client error" do
    client = FakeNotionClient.new
    def client.query_data_source(*) = raise(Notion::Client::Error, "API down")

    result = Notion::WeeklyReviewGenerator.call(@user, date: DATE, client: client)

    refute result.success
    assert_match "API down", result.error
  end
end
