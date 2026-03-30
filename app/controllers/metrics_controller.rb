class MetricsController < ApplicationController
  PER_PAGE = 20

  def index
    @latest_metrics = HealthMetric::METRIC_TYPES.filter_map do |name|
      current_user.health_metrics.by_name(name).order(recorded_at: :desc).first
    end
  end

  def show
    @metric_name = params[:metric_name]
    unless HealthMetric::METRIC_TYPES.include?(@metric_name)
      redirect_to metrics_path, alert: "Unknown metric type."
      return
    end

    metrics = current_user.health_metrics.by_name(@metric_name).order(recorded_at: :desc)

    if params[:from].present? || params[:to].present?
      from_date = params[:from].present? ? Date.parse(params[:from]).beginning_of_day : nil
      to_date = params[:to].present? ? Date.parse(params[:to]).end_of_day : nil
      metrics = metrics.in_date_range(from_date || Time.at(0), to_date || Time.current)
    else
      metrics = metrics.where(recorded_at: 30.days.ago..)
    end

    @chart_data = metrics.map { |m| {date: m.recorded_at.to_date.iso8601, value: m.value.to_f} }

    @page = (params[:page] || 1).to_i
    @total_count = metrics.count
    @metrics = metrics.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
  end
end
