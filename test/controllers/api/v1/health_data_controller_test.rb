require "test_helper"

class Api::V1::HealthDataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_or_create_by!(email: "jules@julescoleman.com") do |u|
      u.password = "password123!"
    end
    @payload = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @token = "test-webhook-token"
    @original_token = ENV["WEBHOOK_AUTH_TOKEN"]
    ENV["WEBHOOK_AUTH_TOKEN"] = @token
  end

  teardown do
    ENV["WEBHOOK_AUTH_TOKEN"] = @original_token
  end

  test "returns 401 without authorization header" do
    post api_v1_health_data_path, params: @payload, as: :json
    assert_response :unauthorized
  end

  test "returns 401 with wrong token" do
    post api_v1_health_data_path,
      params: @payload,
      headers: {"Authorization" => "Bearer wrong-token"},
      as: :json
    assert_response :unauthorized
  end

  test "returns 200 and processes valid payload" do
    post api_v1_health_data_path,
      params: @payload,
      headers: {"Authorization" => "Bearer #{@token}"},
      as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
    assert json["metrics_count"] > 0
    assert json["workouts_count"] > 0
  end

  test "creates a health_payload record associated with user" do
    assert_difference "@user.health_payloads.count", 1 do
      post api_v1_health_data_path,
        params: @payload,
        headers: {"Authorization" => "Bearer #{@token}"},
        as: :json
    end

    assert_equal "processed", @user.health_payloads.last.status
  end

  test "returns 422 on malformed payload" do
    post api_v1_health_data_path,
      params: {data: {metrics: "bad"}},
      headers: {"Authorization" => "Bearer #{@token}"},
      as: :json

    assert_response :unprocessable_entity
    assert_equal "failed", @user.health_payloads.last.status
  end

  test "associates created workouts and metrics with user" do
    post api_v1_health_data_path,
      params: @payload,
      headers: {"Authorization" => "Bearer #{@token}"},
      as: :json

    assert @user.workouts.count > 0
    assert @user.health_metrics.count > 0
  end
end
