class WeeklyReviewJob < ApplicationJob
  retry_on Notion::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform
    user = User.find_by!(email: "jules@julescoleman.com")
    date = Notion::TrainingWeek.today
    result = Notion::WeeklyReviewGenerator.call(user, date: date)
    # The generator rescues internally and returns a failure Result; re-raise so
    # retry_on re-enqueues. This job runs only once a week, so without a retry a
    # transient blip would lose the entire week's review until a manual re-run.
    raise Notion::Client::Error, "WeeklyReviewJob failed for #{date}: #{result.error}" unless result.success
  end
end
