require "test_helper"

class MetricsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user

    @weight = @user.health_metrics.create!(
      metric_name: "weight", recorded_at: 2.days.ago, value: 80.5, units: "kg"
    )
    @weight_old = @user.health_metrics.create!(
      metric_name: "weight", recorded_at: 10.days.ago, value: 81.0, units: "kg"
    )
    @hr = @user.health_metrics.create!(
      metric_name: "resting_heart_rate", recorded_at: 1.day.ago, value: 58, units: "bpm"
    )
    @sleep = @user.health_metrics.create!(
      metric_name: "sleep_analysis", recorded_at: 1.day.ago, value: 7.2, units: "hr",
      metadata: {
        "core" => 3.5, "deep" => 1.8, "rem" => 1.5,
        "sleepStart" => 1.day.ago.change(hour: 22, min: 45).to_s,
        "sleepEnd" => Time.current.change(hour: 6, min: 5).to_s,
        "inBed" => 7.5
      }
    )
  end

  # Index tests

  test "index shows latest value per metric type" do
    get metrics_path
    assert_response :success
    assert_match "Weight", response.body
    assert_match "80.5", response.body
    assert_match "Resting Heart Rate", response.body
    assert_match "Sleep Analysis", response.body
  end

  test "index links to metric detail pages" do
    get metrics_path
    assert_response :success
    assert_select "a[href=?]", metric_path(metric_name: "weight")
    assert_select "a[href=?]", metric_path(metric_name: "sleep_analysis")
  end

  test "index shows empty state when no metrics" do
    HealthMetric.delete_all
    get metrics_path
    assert_response :success
    assert_match "No metrics yet", response.body
  end

  test "index requires authentication" do
    sign_out @user
    get metrics_path
    assert_response :redirect
  end

  # Show tests

  test "show renders metric detail with chart and table" do
    get metric_path(metric_name: "weight")
    assert_response :success
    assert_match "Weight", response.body
    assert_match "80.5", response.body
    assert_match "81", response.body
    assert_select "canvas[data-chart-target='canvas']"
  end

  test "show filters by date range" do
    get metric_path(metric_name: "weight", from: 3.days.ago.to_date.to_s, to: Date.current.to_s)
    assert_response :success
    assert_match "80.5", response.body
    # Old weight outside range
    assert_no_match(/\b81\.0\b/, response.body)
  end

  test "show defaults to last 30 days" do
    @user.health_metrics.create!(
      metric_name: "weight", recorded_at: 60.days.ago, value: 85.0, units: "kg"
    )
    get metric_path(metric_name: "weight")
    assert_response :success
    assert_match "80.5", response.body
    assert_no_match(/\b85\.0\b/, response.body)
  end

  test "show paginates results" do
    25.times do |i|
      @user.health_metrics.create!(
        metric_name: "step_count", recorded_at: (i + 1).days.ago, value: 8000 + i, units: "steps"
      )
    end
    get metric_path(metric_name: "step_count")
    assert_response :success
    assert_match "Page 1 of 2", response.body

    get metric_path(metric_name: "step_count", page: 2)
    assert_response :success
    assert_match "Page 2 of 2", response.body
  end

  test "show displays sleep breakdown toggle" do
    get metric_path(metric_name: "sleep_analysis")
    assert_response :success
    assert_match "7.2", response.body
    assert_select "[data-controller='toggle']"
    assert_match "Core", response.body
    assert_match "Deep", response.body
    assert_match "REM", response.body
  end

  test "show redirects for unknown metric type" do
    get metric_path(metric_name: "fake_metric")
    assert_response :redirect
    assert_redirected_to metrics_path
  end

  test "show requires authentication" do
    sign_out @user
    get metric_path(metric_name: "weight")
    assert_response :redirect
  end

  test "cannot see other user's metrics" do
    other_user = users(:two)
    other_user.health_metrics.create!(
      metric_name: "weight", recorded_at: 1.day.ago, value: 70.0, units: "kg"
    )
    get metric_path(metric_name: "weight")
    assert_response :success
    assert_no_match(/\b70\.0\b/, response.body)
  end
end
