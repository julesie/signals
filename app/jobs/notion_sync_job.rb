class NotionSyncJob < ApplicationJob
  limits_concurrency to: 1, key: "notion_sync"

  def perform
    user = User.find_by!(email: "jules@julescoleman.com")
    client = Notion::Client.new
    today = Notion::TrainingWeek.today

    [today - 1, today].each do |date|
      workout_result = Notion::WorkoutSync.call(user, date: date, client: client)
      Notion::DailyLogSync.call(user, date: date, day_type: workout_result.day_type, client: client)
      workout_result.newly_synced_workout_ids.each do |workout_id|
        WorkoutCommentaryJob.perform_later(workout_id)
      end
    end
  end
end
