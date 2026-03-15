class DashboardController < ApplicationController
  METRIC_TYPES = %w[weight body_fat_percentage vo2_max resting_heart_rate heart_rate_variability step_count active_energy].freeze

  def index
    @latest_metrics = METRIC_TYPES.filter_map do |name|
      HealthMetric.where(metric_name: name).order(recorded_at: :desc).first
    end
    @latest_sleep = HealthMetric.where(metric_name: "sleep_analysis").order(recorded_at: :desc).first
    @recent_workouts = Workout.order(started_at: :desc).limit(5)
    @pipeline_stats = {
      total_payloads: HealthPayload.count,
      last_received: HealthPayload.order(created_at: :desc).first&.created_at,
      failed_count: HealthPayload.where(status: "failed").count
    }
  end
end
