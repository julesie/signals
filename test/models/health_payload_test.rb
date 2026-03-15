require "test_helper"

class HealthPayloadTest < ActiveSupport::TestCase
  test "valid with raw_json and status" do
    payload = HealthPayload.new(raw_json: {data: {}}, status: "pending")
    assert payload.valid?
  end

  test "invalid without raw_json" do
    payload = HealthPayload.new(raw_json: nil, status: "pending")
    assert_not payload.valid?
  end

  test "invalid with unknown status" do
    payload = HealthPayload.new(raw_json: {data: {}}, status: "unknown")
    assert_not payload.valid?
  end
end
