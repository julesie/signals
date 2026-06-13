require "test_helper"
require_relative "fake_notion_client"

class Notion::WorkoutSyncTest < ActiveSupport::TestCase
  DATE = Date.new(2026, 6, 11)

  setup do
    @user = users(:one)
    @orig_week1_start = ENV["TRAINING_WEEK1_START"]
    @orig_workouts_ds_id = ENV["NOTION_WORKOUTS_DS_ID"]
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_WORKOUTS_DS_ID"] = "ds-workouts"
    @started = ActiveSupport::TimeZone["America/Los_Angeles"].local(2026, 6, 11, 7)
  end

  teardown do
    ENV["TRAINING_WEEK1_START"] = @orig_week1_start
    ENV["NOTION_WORKOUTS_DS_ID"] = @orig_workouts_ds_id
  end

  def create_run(attrs = {})
    @user.workouts.create!({
      external_id: SecureRandom.uuid, workout_type: "Running",
      started_at: @started, ended_at: @started + 35.minutes, duration: 2100,
      distance: 5.0, distance_units: "km", energy_burned: 410.4,
      metadata: {"heartRate" => {"avg" => 152.3, "min" => 110, "max" => 171}}
    }.merge(attrs))
  end

  def planned_row(id: "plan-1", type: "Easy", status: "Planned")
    {"id" => id, "properties" => {
      "Type" => {"select" => {"name" => type}},
      "Status" => {"select" => {"name" => status}}
    }}
  end

  test "matches a planned run, fills actuals, sets Done, stores page id" do
    workout = create_run
    client = FakeNotionClient.new(query_results: [[planned_row]])

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert result.success
    assert_equal [workout.id], result.newly_synced_workout_ids
    assert_equal "Easy Run", result.day_type
    assert_equal "plan-1", workout.reload.notion_page_id

    props = client.updates.first[:properties]
    assert_equal 5.0, props["Actual Distance (km)"]["number"]
    assert_equal 35.0, props["Actual Duration (min)"]["number"]
    assert_equal 152.0, props["Actual Avg HR"]["number"]
    assert_equal "7:00/km", props["Actual Avg Pace"]["rich_text"].first["text"]["content"]
    assert_equal 410.0, props["kCal Burned"]["number"]
    assert_equal "Done", props["Status"]["select"]["name"]
    refute props.key?("Felt")
    refute props.key?("Notes")
  end

  test "ignores Skipped and Done rows as candidates and creates unplanned row" do
    workout = create_run(workout_type: "Golf", distance: nil, distance_units: nil, metadata: {})
    client = FakeNotionClient.new(query_results: [[planned_row(status: "Skipped", type: "Golf")]])

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_empty client.updates
    create = client.creates.first
    props = create[:properties]
    assert_equal "W6 Thu - Golf (unplanned)", props["Session"]["title"].first["text"]["content"]
    assert_equal "Golf", props["Type"]["select"]["name"]
    assert_equal "Done", props["Status"]["select"]["name"]
    assert_equal 6.0, props["Week"]["number"]
    assert_equal "created-1", workout.reload.notion_page_id
    assert_equal "Golf", result.day_type
  end

  test "already-linked workout updates its page without re-matching or re-announcing" do
    create_run(notion_page_id: "page-9")
    client = FakeNotionClient.new

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_empty client.queries          # no matching query needed
    assert_equal "page-9", client.updates.first[:page_id]
    refute client.updates.first[:properties].key?("Status")
    assert_empty result.newly_synced_workout_ids
  end

  test "converts miles to km" do
    create_run(distance: 3.1, distance_units: "mi")
    client = FakeNotionClient.new(query_results: [[planned_row]])

    Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_in_delta 4.99, client.updates.first[:properties]["Actual Distance (km)"]["number"], 0.01
  end

  test "long run outranks easy for day_type" do
    create_run
    create_run(started_at: @started + 8.hours, ended_at: @started + 9.hours)
    client = FakeNotionClient.new(query_results: [[planned_row(id: "p1", type: "Easy"), planned_row(id: "p2", type: "Long")], []])

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert_equal "Long Run", result.day_type
  end

  test "no workouts returns nil day_type and success" do
    client = FakeNotionClient.new
    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)
    assert result.success
    assert_nil result.day_type
    assert_empty result.newly_synced_workout_ids
  end

  test "pace rounds correctly when seconds-per-km crosses minute boundary" do
    # 2098 seconds / 5.0 km = 419.6 s/km → rounds to 420 → 7:00/km
    create_run(duration: 2098)
    client = FakeNotionClient.new(query_results: [[planned_row]])

    result = Notion::WorkoutSync.call(@user, date: DATE, client: client)

    assert result.success
    props = client.updates.first[:properties]
    assert_equal "7:00/km", props["Actual Avg Pace"]["rich_text"].first["text"]["content"]
  end
end
