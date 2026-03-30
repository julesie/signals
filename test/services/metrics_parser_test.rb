require "test_helper"

class MetricsParserTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    payload_json = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @metrics_data = payload_json.dig("data", "metrics")
  end

  test "parses simple qty metrics (weight)" do
    weight_data = @metrics_data.find { |m| m["name"] == "weight" }
    result = MetricsParser.call([weight_data], user: @user)

    assert_equal 1, result.created
    metric = @user.health_metrics.find_by(metric_name: "weight")
    assert_equal 82.5, metric.value
    assert_equal "kg", metric.units
  end

  test "parses sleep_analysis with metadata" do
    sleep_data = @metrics_data.find { |m| m["name"] == "sleep_analysis" }
    MetricsParser.call([sleep_data], user: @user)

    metric = @user.health_metrics.find_by(metric_name: "sleep_analysis")
    assert_equal 7.2, metric.value
    assert_equal "hr", metric.units
    assert_equal 1.8, metric.metadata["deep"]
    assert_equal 1.5, metric.metadata["rem"]
  end

  test "parses heart_rate with min/max/avg metadata" do
    hr_data = @metrics_data.find { |m| m["name"] == "heart_rate" }
    MetricsParser.call([hr_data], user: @user)

    # Example payload has 3 HR readings — each stored as its own row
    assert_equal 3, @user.health_metrics.where(metric_name: "heart_rate").count
    metric = @user.health_metrics.where(metric_name: "heart_rate").order(:recorded_at).first
    assert_equal 58, metric.value
    assert_equal 55, metric.metadata["min"]
    assert_equal 62, metric.metadata["max"]
  end

  test "replaces existing metric on same day" do
    weight_data = [{"name" => "step_count", "units" => "count",
                    "data" => [{"qty" => 5000, "date" => "2026-03-14 00:00:00 -0800"}]}]
    MetricsParser.call(weight_data, user: @user)

    updated_data = [{"name" => "step_count", "units" => "count",
                     "data" => [{"qty" => 12000, "date" => "2026-03-14 00:00:00 -0800"}]}]
    result = MetricsParser.call(updated_data, user: @user)

    assert_equal 0, result.created
    assert_equal 1, result.updated
    assert_equal 1, @user.health_metrics.where(metric_name: "step_count").count
    assert_equal 12000, @user.health_metrics.find_by(metric_name: "step_count").value
  end

  test "converts active_energy from kJ to kcal" do
    kj_data = [{"name" => "active_energy", "units" => "kJ",
                "data" => [{"qty" => 4184.0, "date" => "2026-03-14 00:00:00 -0800"}]}]
    MetricsParser.call(kj_data, user: @user)

    metric = @user.health_metrics.find_by(metric_name: "active_energy")
    assert_equal "kcal", metric.units
    assert_in_delta 1000.0, metric.value, 0.1
  end

  test "normalizes weight_body_mass to weight" do
    data = [{"name" => "weight_body_mass", "units" => "kg",
             "data" => [{"qty" => 70.5, "date" => "2026-03-14 00:00:00 -0800"}]}]
    result = MetricsParser.call(data, user: @user)

    assert_equal 1, result.created
    metric = @user.health_metrics.find_by(metric_name: "weight")
    assert_equal 70.5, metric.value
    assert_nil @user.health_metrics.find_by(metric_name: "weight_body_mass")
  end

  test "ignores excluded metrics" do
    ignored = [{"name" => "time_in_daylight", "units" => "min",
                "data" => [{"qty" => 30, "date" => "2026-03-14 00:00:00 -0800"}]}]
    result = MetricsParser.call(ignored, user: @user)

    assert_equal 0, result.created
    assert_equal 0, @user.health_metrics.count
  end

  test "parses all metrics from example payload" do
    result = MetricsParser.call(@metrics_data, user: @user)

    assert result.created > 0
  end
end
