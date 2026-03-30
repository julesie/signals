class DashboardController < ApplicationController
  ACTIVE_CALORIES_GOAL = 500

  def index
    @plan = current_user.plan
    @todays_workouts = current_user.workouts.where(started_at: Date.current.all_day).order(started_at: :desc)
    @latest_metrics = (HealthMetric::METRIC_TYPES - ["sleep_analysis"]).filter_map do |name|
      current_user.health_metrics.by_name(name).order(recorded_at: :desc).first
    end
    @latest_sleep = current_user.health_metrics.by_name("sleep_analysis").order(recorded_at: :desc).first
    @nutrition_profile = current_user.nutrition_profile || current_user.build_nutrition_profile
    @todays_food_logs = current_user.food_logs.on_date(Date.current)
    @pipeline_stats = {
      total_payloads: current_user.health_payloads.count,
      last_received: current_user.health_payloads.order(created_at: :desc).first&.created_at,
      failed_count: current_user.health_payloads.where(status: "failed").count
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
    metrics = current_user.health_metrics.where(metric_name: "active_energy", recorded_at: 7.days.ago..)
    daily = metrics.group_by { |m| m.recorded_at.to_date }.transform_values { |ms| ms.sum(&:value).round }

    @active_calories_days = (6.days.ago.to_date..Date.current).map do |date|
      {date: date, calories: daily[date] || 0}
    end

    @calories_max = [@active_calories_days.map { |d| d[:calories] }.max || 0, ACTIVE_CALORIES_GOAL].max
  end
end
