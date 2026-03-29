class WorkoutsController < ApplicationController
  PER_PAGE = 20

  def index
    workouts = Workout.order(started_at: :desc)
    workouts = workouts.where(workout_type: params[:workout_type]) if params[:workout_type].present?

    if params[:from].present? || params[:to].present?
      from_date = params[:from].present? ? Date.parse(params[:from]).beginning_of_day : nil
      to_date = params[:to].present? ? Date.parse(params[:to]).end_of_day : nil
      workouts = workouts.where(started_at: (from_date || Time.at(0))..(to_date || Time.current))
    else
      workouts = workouts.where(started_at: 30.days.ago..)
    end

    @workout_types = workouts.reorder(nil).distinct.pluck(:workout_type).sort

    @page = (params[:page] || 1).to_i
    @total_count = workouts.count
    @workouts = workouts.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
  end
end
