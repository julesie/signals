require "test_helper"

class MetricsParserTest < ActiveSupport::TestCase
  setup do
    payload_json = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @metrics_data = payload_json.dig("data", "metrics")
  end

  test "parses simple qty metrics (weight) as individual rows" do
    weight_data = @metrics_data.find { |m| m["name"] == "weight" }
    result = MetricsParser.call([weight_data])

    assert_equal 1, result.created
    metric = HealthMetric.find_by(metric_name: "weight")
    assert_equal 82.5, metric.value
    assert_equal "kg", metric.units
  end

  test "parses sleep_analysis with metadata as individual row" do
    sleep_data = @metrics_data.find { |m| m["name"] == "sleep_analysis" }
    MetricsParser.call([sleep_data])

    metric = HealthMetric.find_by(metric_name: "sleep_analysis")
    assert_equal 7.2, metric.value
    assert_equal "hr", metric.units
    assert_equal 1.8, metric.metadata["deep"]
    assert_equal 1.5, metric.metadata["rem"]
  end

  test "aggregates heart_rate to one row per day with min/max/avg" do
    hr_data = @metrics_data.find { |m| m["name"] == "heart_rate" }
    result = MetricsParser.call([hr_data])

    # Example payload has 3 HR readings all on 2026-03-14 → 1 daily row
    assert_equal 1, result.created
    metric = HealthMetric.find_by(metric_name: "heart_rate")
    assert_equal 55, metric.metadata["min"]
    assert_equal 178, metric.metadata["max"]
    assert_equal 3, metric.metadata["count"]
  end

  test "aggregates step_count to daily sum" do
    step_data = @metrics_data.find { |m| m["name"] == "step_count" }
    result = MetricsParser.call([step_data])

    assert_equal 1, result.created
    metric = HealthMetric.find_by(metric_name: "step_count")
    assert_equal 8542, metric.value
    assert_equal "steps", metric.units
  end

  test "aggregates active_energy to daily sum" do
    energy_data = @metrics_data.find { |m| m["name"] == "active_energy" }
    result = MetricsParser.call([energy_data])

    assert_equal 1, result.created
    metric = HealthMetric.find_by(metric_name: "active_energy")
    assert_equal 485, metric.value
  end

  test "converts active_energy from kJ to kcal" do
    kj_data = {
      "name" => "active_energy",
      "units" => "kJ",
      "data" => [
        {"qty" => 4184.0, "date" => "2026-03-14 12:00:00 -0800"},
        {"qty" => 2092.0, "date" => "2026-03-14 14:00:00 -0800"}
      ]
    }
    MetricsParser.call([kj_data])

    metric = HealthMetric.find_by(metric_name: "active_energy")
    assert_equal "kcal", metric.units
    assert_in_delta 1500.0, metric.value, 0.1 # (4184 + 2092) / 4.184
  end

  test "converts basal_energy_burned from kJ to kcal" do
    kj_data = {
      "name" => "basal_energy_burned",
      "units" => "kJ",
      "data" => [{"qty" => 4184.0, "date" => "2026-03-14 08:00:00 -0800"}]
    }
    MetricsParser.call([kj_data])

    metric = HealthMetric.find_by(metric_name: "basal_energy_burned")
    assert_equal "kcal", metric.units
    assert_in_delta 1000.0, metric.value, 0.1
  end

  test "ignores excluded metrics" do
    ignored = {"name" => "time_in_daylight", "units" => "min", "data" => [{"qty" => 30, "date" => "2026-03-14 12:00:00 -0800"}]}
    result = MetricsParser.call([ignored])

    assert_equal 0, result.created
    assert_equal 0, HealthMetric.count
  end

  test "deduplicates on metric_name and recorded_at" do
    weight_data = @metrics_data.find { |m| m["name"] == "weight" }
    MetricsParser.call([weight_data])
    result = MetricsParser.call([weight_data])

    assert_equal 0, result.created
    assert_equal 1, result.skipped
    assert_equal 1, HealthMetric.where(metric_name: "weight").count
  end

  test "deduplicates aggregated metrics by day" do
    hr_data = @metrics_data.find { |m| m["name"] == "heart_rate" }
    MetricsParser.call([hr_data])
    result = MetricsParser.call([hr_data])

    assert_equal 0, result.created
    assert_equal 1, result.skipped
    assert_equal 1, HealthMetric.where(metric_name: "heart_rate").count
  end

  test "parses all metrics from example payload" do
    result = MetricsParser.call(@metrics_data)

    assert result.created > 0
    assert_equal 0, result.skipped
    # Should be far fewer rows than raw data points due to aggregation
    assert HealthMetric.count < 20
  end
end
