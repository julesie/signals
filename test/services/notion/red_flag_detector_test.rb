require "test_helper"

class Notion::RedFlagDetectorTest < ActiveSupport::TestCase
  DATE = Date.new(2026, 6, 12)

  setup do
    @orig_training_week1_start = ENV["TRAINING_WEEK1_START"]
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"

    @user = users(:one)

    # Helper to record a metric on a given date at noon PT
    @tz = ActiveSupport::TimeZone["America/Los_Angeles"]
  end

  teardown do
    ENV["TRAINING_WEEK1_START"] = @orig_training_week1_start
  end

  def record(metric_name, value, date = DATE)
    @user.health_metrics.create!(
      metric_name: metric_name,
      value: value,
      units: "units",
      recorded_at: @tz.local(date.year, date.month, date.day, 12)
    )
  end

  def record_baseline(metric_name, value, days_back:)
    record(metric_name, value, DATE - days_back)
  end

  # --- RHR up ---

  test "RHR up flag trips when today >= baseline + 5" do
    # baseline: 3 readings 1-3 days back, avg 50 bpm
    record_baseline("resting_heart_rate", 50, days_back: 1)
    record_baseline("resting_heart_rate", 50, days_back: 2)
    record_baseline("resting_heart_rate", 50, days_back: 3)
    # today = 55 (exactly at threshold)
    record("resting_heart_rate", 55)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    assert_includes flags, "RHR up"
  end

  test "RHR up flag does not trip when today < baseline + 5" do
    record_baseline("resting_heart_rate", 50, days_back: 1)
    record_baseline("resting_heart_rate", 50, days_back: 2)
    # today = 54 (below threshold)
    record("resting_heart_rate", 54)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    refute_includes flags, "RHR up"
  end

  test "RHR baseline ignores today's value" do
    # Only today's reading — no baseline possible
    record("resting_heart_rate", 80)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    refute_includes flags, "RHR up"
  end

  # --- HRV down ---

  test "HRV down flag trips when today <= baseline * 0.8" do
    # baseline avg = 50ms
    record_baseline("heart_rate_variability", 50, days_back: 1)
    record_baseline("heart_rate_variability", 50, days_back: 2)
    # today = 40 (exactly 80% of 50)
    record("heart_rate_variability", 40)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    assert_includes flags, "HRV down"
  end

  test "HRV down flag does not trip when today > baseline * 0.8" do
    record_baseline("heart_rate_variability", 50, days_back: 1)
    # today = 41 (above 80% of 50)
    record("heart_rate_variability", 41)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    refute_includes flags, "HRV down"
  end

  test "HRV baseline ignores today's value" do
    record("heart_rate_variability", 10)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    refute_includes flags, "HRV down"
  end

  # --- Sleep short ---

  test "Sleep <6.5h flag trips when sleep < 6.5" do
    record("sleep_analysis", 6.0)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    assert_includes flags, "Sleep <6.5h"
  end

  test "Sleep <6.5h flag does not trip when sleep >= 6.5" do
    record("sleep_analysis", 6.5)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    refute_includes flags, "Sleep <6.5h"
  end

  # --- Weight loss too fast ---

  test "Weight loss too fast flag trips when lost > 1 kg vs ~7 days ago" do
    # ~7 days ago: 65 kg
    record("weight", 65.0, DATE - 7)
    # today: 63.9 kg (lost 1.1 kg)
    record("weight", 63.9)

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    assert_includes flags, "Weight loss too fast"
  end

  test "Weight loss too fast flag does not trip when loss <= 1 kg" do
    record("weight", 65.0, DATE - 7)
    record("weight", 64.1) # lost 0.9 kg

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    refute_includes flags, "Weight loss too fast"
  end

  test "Weight loss too fast uses nearest reading within 7-9 days back" do
    # No reading exactly 7 days back, but 8 days back
    record("weight", 66.0, DATE - 8)
    record("weight", 64.9) # lost 1.1 kg vs 8 days ago

    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    assert_includes flags, "Weight loss too fast"
  end

  # --- No flags with no data ---

  test "returns empty array when no health metrics exist" do
    flags = Notion::RedFlagDetector.call(@user, date: DATE)
    assert_equal [], flags
  end
end
