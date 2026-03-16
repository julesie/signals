require "test_helper"

class HealthDataReprocessorTest < ActiveSupport::TestCase
  test "deduplicates overlapping payloads — latest wins" do
    # First payload: partial day
    HealthPayload.create!(raw_json: {
      "data" => {"metrics" => [
        {"name" => "step_count", "units" => "count", "data" => [
          {"qty" => 5000, "date" => "2026-03-14 00:00:00 -0800"}
        ]}
      ]}
    })

    # Second payload: same day, updated total (latest wins)
    HealthPayload.create!(raw_json: {
      "data" => {"metrics" => [
        {"name" => "step_count", "units" => "count", "data" => [
          {"qty" => 12000, "date" => "2026-03-14 00:00:00 -0800"}
        ]}
      ]}
    })

    HealthDataReprocessor.call

    assert_equal 1, HealthMetric.where(metric_name: "step_count").count
    assert_equal 12000, HealthMetric.find_by(metric_name: "step_count").value
  end

  test "deduplicates workouts by external_id across payloads" do
    HealthPayload.create!(raw_json: {
      "data" => {"workouts" => [
        {"id" => "ABC-123", "name" => "Running", "start" => "2026-03-14 07:00:00 -0800",
         "end" => "2026-03-14 08:00:00 -0800", "duration" => 3600}
      ]}
    })

    HealthPayload.create!(raw_json: {
      "data" => {"workouts" => [
        {"id" => "ABC-123", "name" => "Running", "start" => "2026-03-14 07:00:00 -0800",
         "end" => "2026-03-14 08:00:00 -0800", "duration" => 3600}
      ]}
    })

    HealthDataReprocessor.call

    assert_equal 1, Workout.count
  end

  test "marks all payloads as processed" do
    HealthPayload.create!(raw_json: {"data" => {"metrics" => []}}, status: "failed", error_message: "old error")
    HealthPayload.create!(raw_json: {"data" => {"metrics" => []}}, status: "pending")

    HealthDataReprocessor.call

    assert HealthPayload.where.not(status: "processed").none?
    assert HealthPayload.where.not(error_message: nil).none?
  end
end
