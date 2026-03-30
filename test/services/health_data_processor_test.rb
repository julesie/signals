require "test_helper"

class HealthDataProcessorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    raw_json = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @payload = @user.health_payloads.create!(raw_json: raw_json, status: "pending")
  end

  test "processes a valid payload end-to-end" do
    result = HealthDataProcessor.call(@payload, user: @user)

    assert result.success
    assert result.metrics_created > 0
    assert result.workouts_created > 0
    assert_equal "processed", @payload.reload.status
  end

  test "marks payload as failed on error" do
    @payload.update!(raw_json: {"data" => {"metrics" => "not_an_array"}})
    result = HealthDataProcessor.call(@payload, user: @user)

    assert_not result.success
    assert_equal "failed", @payload.reload.status
    assert @payload.error_message.present?
  end

  test "rolls back all records on partial failure" do
    @payload.update!(raw_json: {"data" => {"metrics" => [], "workouts" => "bad"}})
    HealthDataProcessor.call(@payload, user: @user)

    assert_equal 0, @user.health_metrics.count
    assert_equal 0, @user.workouts.count
  end

  test "handles payload with only metrics (no workouts key)" do
    @payload.update!(raw_json: {"data" => {"metrics" => @payload.raw_json.dig("data", "metrics")}})
    result = HealthDataProcessor.call(@payload, user: @user)

    assert result.success
    assert result.metrics_created > 0
    assert_equal 0, result.workouts_created
  end
end
