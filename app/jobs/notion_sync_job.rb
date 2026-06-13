class NotionSyncJob < ApplicationJob
  limits_concurrency to: 1, key: "notion_sync"
  retry_on Notion::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform
    user = User.find_by!(email: "jules@julescoleman.com")
    client = Notion::Client.new
    today = Notion::TrainingWeek.today
    errors = []

    [today - 1, today].each do |date|
      workout_result = Notion::WorkoutSync.call(user, date: date, client: client)
      errors << "WorkoutSync(#{date}): #{workout_result.error}" unless workout_result.success

      daily_result = Notion::DailyLogSync.call(user, date: date, day_type: workout_result.day_type, client: client)
      errors << "DailyLogSync(#{date}): #{daily_result.error}" unless daily_result.success

      workout_result.newly_synced_workout_ids.each do |workout_id|
        WorkoutCommentaryJob.perform_later(workout_id)
      end
    end

    raise Notion::Client::Error, "NotionSyncJob partial failure: #{errors.join("; ")}" if errors.any?
  end
end
