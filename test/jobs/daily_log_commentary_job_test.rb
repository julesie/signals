require "test_helper"

class DailyLogCommentaryJobTest < ActiveJob::TestCase
  setup do
    @orig_notion_api_token = ENV["NOTION_API_TOKEN"]
    @orig_training_week1_start = ENV["TRAINING_WEEK1_START"]
    @orig_notion_daily_logs_ds_id = ENV["NOTION_DAILY_LOGS_DS_ID"]

    ENV["NOTION_API_TOKEN"] = "test-token"
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_DAILY_LOGS_DS_ID"] = "ds-daily"

    @user = users(:one)
    @user.update!(email: "jules@julescoleman.com")
  end

  teardown do
    ENV["NOTION_API_TOKEN"] = @orig_notion_api_token
    ENV["TRAINING_WEEK1_START"] = @orig_training_week1_start
    ENV["NOTION_DAILY_LOGS_DS_ID"] = @orig_notion_daily_logs_ds_id
  end

  test "perform calls the generator with the hardcoded user and today's date" do
    called_with_user = nil
    called_with_date = nil
    success_result = Notion::DailyLogCommentaryGenerator::Result.new(
      success: true, narrative: "Good day.", flags: []
    )

    orig_call = Notion::DailyLogCommentaryGenerator.method(:call)
    Notion::DailyLogCommentaryGenerator.define_singleton_method(:call) do |user, date:, **_|
      called_with_user = user
      called_with_date = date
      success_result
    end

    DailyLogCommentaryJob.perform_now

    assert_equal @user.id, called_with_user.id
    assert_equal Notion::TrainingWeek.today, called_with_date
  ensure
    Notion::DailyLogCommentaryGenerator.define_singleton_method(:call, orig_call)
  end

  test "failure path re-raises so retry_on re-enqueues instead of silently dropping" do
    failure_result = Notion::DailyLogCommentaryGenerator::Result.new(
      success: false, error: "something went wrong"
    )

    orig_call = Notion::DailyLogCommentaryGenerator.method(:call)
    Notion::DailyLogCommentaryGenerator.define_singleton_method(:call) do |user, date:, **_|
      failure_result
    end

    # The generator swallows exceptions into a failure Result, so the job
    # re-raises Notion::Client::Error to let retry_on re-enqueue a retry
    # rather than losing the day's narrative to a single log line.
    assert_enqueued_with(job: DailyLogCommentaryJob) do
      DailyLogCommentaryJob.perform_now
    end
  ensure
    Notion::DailyLogCommentaryGenerator.define_singleton_method(:call, orig_call)
  end
end
