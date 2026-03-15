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
