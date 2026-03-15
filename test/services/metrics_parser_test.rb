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
    MetricsParser.call([sleep_data])

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
