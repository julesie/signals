require "test_helper"

class WorkoutTest < ActiveSupport::TestCase
  test "valid with all required fields" do
    workout = Workout.new(
      external_id: "ABC-123", workout_type: "Running",
      started_at: 1.hour.ago, ended_at: Time.current,
      duration: 3600
    )
    assert workout.valid?
  end

  test "invalid without external_id" do
    workout = Workout.new(workout_type: "Running", started_at: 1.hour.ago, ended_at: Time.current, duration: 3600)
    assert_not workout.valid?
  end

  test "enforces uniqueness on external_id" do
    Workout.create!(external_id: "ABC-123", workout_type: "Running", started_at: 1.hour.ago, ended_at: Time.current, duration: 3600)
    duplicate = Workout.new(external_id: "ABC-123", workout_type: "Running", started_at: 1.hour.ago, ended_at: Time.current, duration: 3600)
    assert_not duplicate.valid?
  end
end
