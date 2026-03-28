require "test_helper"

class WorkoutParserTest < ActiveSupport::TestCase
  setup do
    payload_json = JSON.parse(File.read(Rails.root.join("docs/example_workout_payload.json")))
    @workouts_data = payload_json.dig("data", "workouts")
  end

  test "parses a running workout with common fields" do
    result = WorkoutParser.call(@workouts_data)

    assert_equal 1, result.created
    workout = Workout.find_by(external_id: "F4A3B2C1-1234-5678-9ABC-DEF012345678")
    assert_equal "Running", workout.workout_type
    assert_equal 2700, workout.duration
    assert_in_delta 8.04, workout.distance
    assert_equal "km", workout.distance_units
    assert_in_delta 485.3, workout.energy_burned
  end

  test "stores time-series and route data in metadata" do
    WorkoutParser.call(@workouts_data)
    workout = Workout.first

    assert workout.metadata["heartRateData"].is_a?(Array)
    assert workout.metadata["route"].is_a?(Array)
    assert_equal 9, workout.metadata["heartRateData"].length
    assert_equal 3, workout.metadata["route"].length
  end

  test "stores heart rate summary in metadata" do
    WorkoutParser.call(@workouts_data)
    workout = Workout.first

    assert_equal 155, workout.metadata.dig("heartRate", "avg")
    assert_equal 178, workout.metadata.dig("heartRate", "max")
    assert_equal 98, workout.metadata.dig("heartRate", "min")
  end

  test "converts energy_burned from kJ to kcal" do
    @workouts_data.first["activeEnergyBurned"] = {"qty" => 2030.3, "units" => "kJ"}
    WorkoutParser.call(@workouts_data)

    workout = Workout.first
    assert_in_delta 485.5, workout.energy_burned, 0.5
  end

  test "deduplicates on external_id" do
    WorkoutParser.call(@workouts_data)
    result = WorkoutParser.call(@workouts_data)

    assert_equal 0, result.created
    assert_equal 1, result.skipped
    assert_equal 1, Workout.count
  end
end
