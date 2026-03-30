require "test_helper"

class HealthMetricTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid with all required fields" do
    metric = @user.health_metrics.new(
      metric_name: "weight", recorded_at: Time.current,
      value: 82.5, units: "kg"
    )
    assert metric.valid?
  end

  test "invalid without metric_name" do
    metric = @user.health_metrics.new(recorded_at: Time.current, value: 82.5, units: "kg")
    assert_not metric.valid?
  end

  test "enforces uniqueness on user, metric_name, and recorded_at" do
    time = Time.current
    @user.health_metrics.create!(metric_name: "weight", recorded_at: time, value: 82.5, units: "kg")
    duplicate = @user.health_metrics.new(metric_name: "weight", recorded_at: time, value: 83.0, units: "kg")
    assert_not duplicate.valid?
  end

  test "allows same metric_name and recorded_at for different users" do
    time = Time.current
    other_user = users(:two)
    @user.health_metrics.create!(metric_name: "weight", recorded_at: time, value: 82.5, units: "kg")
    other_metric = other_user.health_metrics.new(metric_name: "weight", recorded_at: time, value: 75.0, units: "kg")
    assert other_metric.valid?
  end
end
