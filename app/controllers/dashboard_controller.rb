class DashboardController < ApplicationController
  METRIC_TYPES = %w[weight body_fat_percentage vo2_max resting_heart_rate heart_rate_variability step_count active_energy dietary_energy].freeze
  ACTIVE_CALORIES_GOAL = 500

  def index
    @plan = current_user.plan
    @todays_workouts = Workout.where(started_at: Date.current.all_day).order(started_at: :desc)
    @latest_metrics = METRIC_TYPES.filter_map do |name|
      HealthMetric.where(metric_name: name).order(recorded_at: :desc).first
    end
    @latest_sleep = HealthMetric.where(metric_name: "sleep_analysis").order(recorded_at: :desc).first
    @pipeline_stats = {
      total_payloads: HealthPayload.count,
      last_received: HealthPayload.order(created_at: :desc).first&.created_at,
      failed_count: HealthPayload.where(status: "failed").count
    }
  end

  def suggestion
    @plan = current_user.plan
    generate_suggestion_if_needed
    render layout: false
  end

  def regenerate_suggestion
    @plan = current_user.plan || current_user.create_plan
    @result = PlanSuggestionGenerator.call(@plan)
    @plan.reload
    render :suggestion, layout: false
  end

  def adherence
    @plan = current_user.plan
    generate_adherence_if_needed
    load_active_calories
    render layout: false
  end

  def regenerate_adherence
    @plan = current_user.plan || current_user.create_plan
    @result = PlanAdherenceGenerator.call(@plan)
    @plan.reload
    load_active_calories
    render :adherence, layout: false
  end

  private

  def generate_suggestion_if_needed
    return unless @plan&.has_content?
    return if @plan.suggestion_generated_at&.to_date == Date.current

    @result = PlanSuggestionGenerator.call(@plan)
    @plan.reload
  end

  def generate_adherence_if_needed
    return unless @plan&.has_content?
    return if @plan.adherence_summary_generated_at&.to_date == Date.current

    @result = PlanAdherenceGenerator.call(@plan)
    @plan.reload
  end

  def load_active_calories
    metrics = HealthMetric.where(metric_name: "active_energy", recorded_at: 7.days.ago..)
    daily = metrics.group_by { |m| m.recorded_at.to_date }.transform_values { |ms| ms.sum(&:value).round }

    @active_calories_days = (6.days.ago.to_date..Date.current).map do |date|
      {date: date, calories: daily[date] || 0}
    end

    @calories_max = [@active_calories_days.map { |d| d[:calories] }.max || 0, ACTIVE_CALORIES_GOAL].max
  end
end
