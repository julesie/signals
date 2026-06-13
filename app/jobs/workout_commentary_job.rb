class WorkoutCommentaryJob < ApplicationJob
  def perform(workout_id)
    workout = Workout.find(workout_id)
    result = Notion::WorkoutCommentaryGenerator.call(workout)
    unless result.success
      Rails.logger.error("WorkoutCommentaryJob failed for Workout##{workout_id}: #{result.error}")
    end
  end
end
