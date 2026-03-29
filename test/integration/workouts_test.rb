require "test_helper"

class WorkoutsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user

    @run = Workout.create!(
      external_id: "w-run", workout_type: "Outdoor Run",
      started_at: 2.days.ago, ended_at: 2.days.ago + 30.minutes,
      duration: 1800, distance: 5.0, distance_units: "km", energy_burned: 300,
      metadata: {"heartRate" => {"avg" => 155}}
    )
    @swim = Workout.create!(
      external_id: "w-swim", workout_type: "Pool Swim",
      started_at: 1.day.ago, ended_at: 1.day.ago + 40.minutes,
      duration: 2400, energy_burned: 400
    )
  end

  test "workouts index shows all workouts" do
    get workouts_path
    assert_response :success
    assert_match "Outdoor Run", response.body
    assert_match "Pool Swim", response.body
  end

  test "workouts index filters by workout type" do
    get workouts_path, params: {workout_type: "Outdoor Run"}
    assert_response :success
    assert_match "1 workout", response.body
    # Pool Swim should still appear in the dropdown but not in results
    assert_select "select[name=workout_type] option[value='Pool Swim']"
    assert_select "td.px-6", text: "Pool Swim", count: 0
  end

  test "workouts index filters by date range" do
    get workouts_path, params: {from: 3.days.ago.to_date.to_s, to: 1.day.ago.to_date.to_s}
    assert_response :success
    assert_match "Outdoor Run", response.body
  end

  test "workouts index shows empty state" do
    Workout.delete_all
    get workouts_path
    assert_response :success
    assert_match "No workouts found", response.body
  end

  test "workouts index requires authentication" do
    sign_out @user
    get workouts_path
    assert_response :redirect
  end
end
