require "test_helper"

class WorkoutCommentaryJobTest < ActiveJob::TestCase
  setup do
    @orig_notion_api_token = ENV["NOTION_API_TOKEN"]
    ENV["NOTION_API_TOKEN"] = "test-token"

    @user = users(:one)
    @workout = @user.workouts.create!(
      external_id: "commentary-job-test-#{SecureRandom.hex(4)}",
      workout_type: "Running",
      started_at: 1.day.ago,
      ended_at: 1.day.ago + 30.minutes,
      duration: 1800,
      notion_page_id: "notion-page-job-test"
    )
  end

  teardown do
    ENV["NOTION_API_TOKEN"] = @orig_notion_api_token
  end

  test "perform calls the generator with the workout" do
    called_with = nil
    success_result = Notion::WorkoutCommentaryGenerator::Result.new(success: true, commentary: "Great run!")

    orig_call = Notion::WorkoutCommentaryGenerator.method(:call)
    Notion::WorkoutCommentaryGenerator.define_singleton_method(:call) do |workout, **_|
      called_with = workout
      success_result
    end

    WorkoutCommentaryJob.perform_now(@workout.id)

    assert_equal @workout.id, called_with.id
  ensure
    Notion::WorkoutCommentaryGenerator.define_singleton_method(:call, orig_call)
  end

  test "failure path logs without raising" do
    failure_result = Notion::WorkoutCommentaryGenerator::Result.new(success: false, error: "something went wrong")

    orig_call = Notion::WorkoutCommentaryGenerator.method(:call)
    Notion::WorkoutCommentaryGenerator.define_singleton_method(:call) do |workout, **_|
      failure_result
    end

    assert_nothing_raised do
      WorkoutCommentaryJob.perform_now(@workout.id)
    end
  ensure
    Notion::WorkoutCommentaryGenerator.define_singleton_method(:call, orig_call)
  end
end
