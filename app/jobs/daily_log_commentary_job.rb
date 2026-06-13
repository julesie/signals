class DailyLogCommentaryJob < ApplicationJob
  def perform
    user = User.find_by!(email: "jules@julescoleman.com")
    date = Notion::TrainingWeek.today
    result = Notion::DailyLogCommentaryGenerator.call(user, date: date)
    unless result.success
      Rails.logger.error("DailyLogCommentaryJob failed for #{date}: #{result.error}")
    end
  end
end
