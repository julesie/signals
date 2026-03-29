require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user

    HealthMetric.create!(metric_name: "weight", recorded_at: 1.hour.ago, value: 82.5, units: "kg")
    HealthMetric.create!(metric_name: "resting_heart_rate", recorded_at: 1.hour.ago, value: 58, units: "bpm")
    HealthMetric.create!(
      metric_name: "sleep_analysis", recorded_at: 1.hour.ago, value: 7.2, units: "hr",
      metadata: {"core" => 3.5, "deep" => 1.8, "rem" => 1.5,
                 "sleepStart" => "2026-03-13 22:45:00", "sleepEnd" => "2026-03-14 06:05:00",
                 "inBed" => 7.5}
    )
    HealthPayload.create!(raw_json: {data: {}}, status: "processed")
  end

  test "dashboard shows metric values" do
    get root_path
    assert_response :success
    assert_match "82.5", response.body
    assert_match "58", response.body
  end

  test "dashboard shows sleep data" do
    get root_path
    assert_match "7.2", response.body
  end

  test "dashboard shows today's workouts" do
    Workout.create!(
      external_id: "today-run", workout_type: "Running",
      started_at: 2.hours.ago, ended_at: 1.hour.ago, duration: 3600,
      distance: 10.0, distance_units: "km", energy_burned: 600
    )
    get root_path
    assert_match "Running", response.body
    assert_match "Today's Workouts", response.body
  end

  test "dashboard shows empty state when no workouts today" do
    get root_path
    assert_match "No workouts recorded today", response.body
  end

  test "dashboard shows pipeline status" do
    get root_path
    assert_match "processed", response.body.downcase
  end

  test "dashboard has turbo frames for suggestion and adherence" do
    get root_path
    assert_match 'turbo-frame id="suggestion"', response.body
    assert_match 'turbo-frame id="adherence"', response.body
  end

  test "dashboard has link to workouts page" do
    get root_path
    assert_match "View all", response.body
  end

  test "dashboard renders without data" do
    HealthMetric.delete_all
    Workout.delete_all
    HealthPayload.delete_all
    get root_path
    assert_response :success
  end

  test "suggestion endpoint returns turbo frame" do
    get dashboard_suggestion_path
    assert_response :success
    assert_match "turbo-frame", response.body
  end

  test "adherence endpoint returns turbo frame" do
    get dashboard_adherence_path
    assert_response :success
    assert_match "turbo-frame", response.body
  end

  test "regenerate suggestion via POST returns turbo frame" do
    post dashboard_suggestion_path
    assert_response :success
    assert_match "turbo-frame", response.body
  end

  test "regenerate adherence via POST returns turbo frame" do
    post dashboard_adherence_path
    assert_response :success
    assert_match "turbo-frame", response.body
  end
end
