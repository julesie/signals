require "test_helper"

class Api::V1::HealthDataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @payload = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @token = "test-webhook-token"
    ENV["WEBHOOK_AUTH_TOKEN"] = @token
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

  test "creates a health_payload record" do
    assert_difference "HealthPayload.count", 1 do
      post api_v1_health_data_path,
        params: @payload,
        headers: {"Authorization" => "Bearer #{@token}"},
        as: :json
    end

    assert_equal "processed", HealthPayload.last.status
  end

  test "returns 422 on malformed payload" do
    post api_v1_health_data_path,
      params: {data: {metrics: "bad"}},
      headers: {"Authorization" => "Bearer #{@token}"},
      as: :json

    assert_response :unprocessable_entity
    assert_equal "failed", HealthPayload.last.status
  end
end
