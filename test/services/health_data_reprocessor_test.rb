require "test_helper"

class HealthDataReprocessorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "deduplicates overlapping payloads — latest wins" do
    # First payload: partial day
    @user.health_payloads.create!(raw_json: {
      "data" => {"metrics" => [
        {"name" => "step_count", "units" => "count", "data" => [
          {"qty" => 5000, "date" => "2026-03-14 00:00:00 -0800"}
        ]}
      ]}
    })

    # Second payload: same day, updated total (latest wins)
    @user.health_payloads.create!(raw_json: {
      "data" => {"metrics" => [
        {"name" => "step_count", "units" => "count", "data" => [
          {"qty" => 12000, "date" => "2026-03-14 00:00:00 -0800"}
        ]}
      ]}
    })

    HealthDataReprocessor.call

    assert_equal 1, @user.health_metrics.where(metric_name: "step_count").count
    assert_equal 12000, @user.health_metrics.find_by(metric_name: "step_count").value
  end

  test "deduplicates workouts by external_id across payloads" do
    @user.health_payloads.create!(raw_json: {
      "data" => {"workouts" => [
        {"id" => "ABC-123", "name" => "Running", "start" => "2026-03-14 07:00:00 -0800",
         "end" => "2026-03-14 08:00:00 -0800", "duration" => 3600}
      ]}
    })

    @user.health_payloads.create!(raw_json: {
      "data" => {"workouts" => [
        {"id" => "ABC-123", "name" => "Running", "start" => "2026-03-14 07:00:00 -0800",
         "end" => "2026-03-14 08:00:00 -0800", "duration" => 3600}
      ]}
    })

    HealthDataReprocessor.call

    assert_equal 1, @user.workouts.count
  end

  test "marks all payloads as processed" do
    @user.health_payloads.create!(raw_json: {"data" => {"metrics" => []}}, status: "failed", error_message: "old error")
    @user.health_payloads.create!(raw_json: {"data" => {"metrics" => []}}, status: "pending")

    HealthDataReprocessor.call

    assert HealthPayload.where.not(status: "processed").none?
    assert HealthPayload.where.not(error_message: nil).none?
  end

  test "scopes deletes to the user — does not affect other users" do
    other_user = users(:two)

    @user.health_payloads.create!(raw_json: {
      "data" => {"metrics" => [
        {"name" => "step_count", "units" => "count", "data" => [
          {"qty" => 8000, "date" => "2026-03-14 00:00:00 -0800"}
        ]}
      ]}
    })

    other_user.workouts.create!(
      external_id: "other-run", workout_type: "Running",
      started_at: 1.day.ago, ended_at: 1.day.ago + 30.minutes, duration: 1800
    )
    other_user.health_metrics.create!(
      metric_name: "weight", recorded_at: 1.day.ago, value: 75.0, units: "kg"
    )

    HealthDataReprocessor.call

    # Other user's data should be untouched
    assert_equal 1, other_user.workouts.count
    assert_equal 1, other_user.health_metrics.count
  end
end
