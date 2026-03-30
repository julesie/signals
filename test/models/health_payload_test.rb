require "test_helper"

class HealthPayloadTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid with raw_json and status" do
    payload = @user.health_payloads.new(raw_json: {data: {}}, status: "pending")
    assert payload.valid?
  end

  test "invalid without raw_json" do
    payload = @user.health_payloads.new(raw_json: nil, status: "pending")
    assert_not payload.valid?
  end

  test "invalid with unknown status" do
    payload = @user.health_payloads.new(raw_json: {data: {}}, status: "unknown")
    assert_not payload.valid?
  end
end
