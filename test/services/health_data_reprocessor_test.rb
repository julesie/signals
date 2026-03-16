require "test_helper"

class HealthDataReprocessorTest < ActiveSupport::TestCase
  test "deduplicates overlapping payloads by timestamp" do
    # Simulate two overlapping cumulative payloads
    HealthPayload.create!(raw_json: {
      "data" => {"metrics" => [
        {"name" => "step_count", "units" => "steps", "data" => [
          {"qty" => 100, "date" => "2026-03-14 09:00:00 -0800"},
          {"qty" => 200, "date" => "2026-03-14 10:00:00 -0800"}
        ]}
      ]}
    })

    HealthPayload.create!(raw_json: {
      "data" => {"metrics" => [
        {"name" => "step_count", "units" => "steps", "data" => [
          {"qty" => 100, "date" => "2026-03-14 09:00:00 -0800"},
          {"qty" => 200, "date" => "2026-03-14 10:00:00 -0800"},
          {"qty" => 300, "date" => "2026-03-14 11:00:00 -0800"}
        ]}
      ]}
    })

    results = HealthDataReprocessor.call

    assert_equal 1, results[:metrics].created
    metric = HealthMetric.find_by(metric_name: "step_count")
    # Should be 100 + 200 + 300 = 600, NOT 100+200+100+200+300 = 900
    assert_equal 600, metric.value
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

    results = HealthDataReprocessor.call

    assert_equal 1, results[:workouts].created
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
