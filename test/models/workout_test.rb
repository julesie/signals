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

  test "valid with blank notes" do
    workout = Workout.new(
      external_id: "NOTE-1", workout_type: "Running",
      started_at: 1.hour.ago, ended_at: Time.current,
      duration: 3600, notes: ""
    )
    assert workout.valid?
  end

  test "valid with nil notes" do
    workout = Workout.new(
      external_id: "NOTE-2", workout_type: "Running",
      started_at: 1.hour.ago, ended_at: Time.current,
      duration: 3600, notes: nil
    )
    assert workout.valid?
  end

  test "valid with notes within 280 characters" do
    workout = Workout.new(
      external_id: "NOTE-3", workout_type: "Running",
      started_at: 1.hour.ago, ended_at: Time.current,
      duration: 3600, notes: "Knee felt tight on hills"
    )
    assert workout.valid?
  end

  test "invalid with notes exceeding 280 characters" do
    workout = Workout.new(
      external_id: "NOTE-4", workout_type: "Running",
      started_at: 1.hour.ago, ended_at: Time.current,
      duration: 3600, notes: "a" * 281
    )
    assert_not workout.valid?
    assert_includes workout.errors[:notes], "is too long (maximum is 280 characters)"
  end
end
