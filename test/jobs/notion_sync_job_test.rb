require "test_helper"
require_relative "../services/notion/fake_notion_client"

class NotionSyncJobTest < ActiveJob::TestCase
  setup do
    @orig_week1_start = ENV["TRAINING_WEEK1_START"]
    @orig_daily_ds_id = ENV["NOTION_DAILY_LOGS_DS_ID"]
    @orig_workouts_ds_id = ENV["NOTION_WORKOUTS_DS_ID"]
    @orig_notion_api_token = ENV["NOTION_API_TOKEN"]
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_DAILY_LOGS_DS_ID"] = "ds-daily"
    ENV["NOTION_WORKOUTS_DS_ID"] = "ds-workouts"
    ENV["NOTION_API_TOKEN"] = "test-token"
    @user = users(:one)
    @user.update!(email: "jules@julescoleman.com")
  end

  teardown do
    ENV["TRAINING_WEEK1_START"] = @orig_week1_start
    ENV["NOTION_DAILY_LOGS_DS_ID"] = @orig_daily_ds_id
    ENV["NOTION_WORKOUTS_DS_ID"] = @orig_workouts_ds_id
    ENV["NOTION_API_TOKEN"] = @orig_notion_api_token
  end

  test "syncs workouts then daily log for yesterday and today, enqueues commentary for new syncs" do
    calls = []
    workout_result = Notion::WorkoutSync::Result.new(
      success: true, newly_synced_workout_ids: [42], day_type: "Easy Run"
    )
    daily_result = Notion::DailyLogSync::Result.new(success: true, page_id: "p", created: false)

    orig_workout_call = Notion::WorkoutSync.method(:call)
    orig_daily_call = Notion::DailyLogSync.method(:call)

    Notion::WorkoutSync.define_singleton_method(:call) do |user, date:, client:|
      calls << [:workout, date]
      workout_result
    end
    Notion::DailyLogSync.define_singleton_method(:call) do |user, date:, day_type:, client:|
      calls << [:daily, date, day_type]
      daily_result
    end

    NotionSyncJob.perform_now

    today = Notion::TrainingWeek.today
    assert_equal [:workout, today - 1], calls[0]
    assert_equal [:daily, today - 1, "Easy Run"], calls[1]
    assert_equal [:workout, today], calls[2]
    assert_enqueued_with(job: WorkoutCommentaryJob, args: [42])
  ensure
    Notion::WorkoutSync.define_singleton_method(:call, orig_workout_call)
    Notion::DailyLogSync.define_singleton_method(:call, orig_daily_call)
  end
end
