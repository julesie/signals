class DailyLogCommentaryJob < ApplicationJob
  retry_on Notion::Client::Error, wait: :polynomially_longer, attempts: 3

  def perform
    user = User.find_by!(email: "jules@julescoleman.com")
    date = Notion::TrainingWeek.today
    result = Notion::DailyLogCommentaryGenerator.call(user, date: date)
    # The generator rescues internally and returns a failure Result; re-raise so
    # retry_on re-enqueues. No catch-up job re-runs commentary, so without this a
    # transient Notion/LLM blip would silently drop the day's narrative.
    raise Notion::Client::Error, "DailyLogCommentaryJob failed for #{date}: #{result.error}" unless result.success
  end
end
