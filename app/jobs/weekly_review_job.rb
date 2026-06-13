class WeeklyReviewJob < ApplicationJob
  def perform
    user = User.find_by!(email: "jules@julescoleman.com")
    date = Notion::TrainingWeek.today
    result = Notion::WeeklyReviewGenerator.call(user, date: date)
    unless result.success
      Rails.logger.error("WeeklyReviewJob failed for #{date}: #{result.error}")
    end
  end
end
