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
    assert_equal 4, calls.size
    assert_equal [:workout, today - 1], calls[0]
    assert_equal [:daily, today - 1, "Easy Run"], calls[1]
    assert_equal [:workout, today], calls[2]
    assert_equal [:daily, today, "Easy Run"], calls[3]
    assert_enqueued_with(job: WorkoutCommentaryJob, args: [42])
  ensure
    Notion::WorkoutSync.define_singleton_method(:call, orig_workout_call)
    Notion::DailyLogSync.define_singleton_method(:call, orig_daily_call)
  end

  test "retries after processing both dates when WorkoutSync fails, still calls DailyLogSync for both" do
    daily_calls = []
    failed_workout_result = Notion::WorkoutSync::Result.new(
      success: false, error: "boom", newly_synced_workout_ids: [], day_type: nil
    )
    daily_result = Notion::DailyLogSync::Result.new(success: true, page_id: "p", created: false)

    orig_workout_call = Notion::WorkoutSync.method(:call)
    orig_daily_call = Notion::DailyLogSync.method(:call)

    Notion::WorkoutSync.define_singleton_method(:call) do |user, date:, client:|
      failed_workout_result
    end
    Notion::DailyLogSync.define_singleton_method(:call) do |user, date:, day_type:, client:|
      daily_calls << date
      daily_result
    end

    # The partial-failure raise is a Notion::Client::Error, which retry_on
    # intercepts and re-enqueues rather than letting it propagate.
    assert_enqueued_with(job: NotionSyncJob) do
      NotionSyncJob.perform_now
    end

    today = Notion::TrainingWeek.today
    assert_equal 2, daily_calls.size, "DailyLogSync should be called for both dates even on partial failure"
    assert_includes daily_calls, today - 1
    assert_includes daily_calls, today
  ensure
    Notion::WorkoutSync.define_singleton_method(:call, orig_workout_call)
    Notion::DailyLogSync.define_singleton_method(:call, orig_daily_call)
  end
end
