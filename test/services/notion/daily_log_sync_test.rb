require "test_helper"
require_relative "fake_notion_client"

class Notion::DailyLogSyncTest < ActiveSupport::TestCase
  DATE = Date.new(2026, 6, 11)

  setup do
    @user = users(:one)
    @original_week1_start = ENV["TRAINING_WEEK1_START"]
    @original_ds_id = ENV["NOTION_DAILY_LOGS_DS_ID"]
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_DAILY_LOGS_DS_ID"] = "ds-daily"
    noon_pt = ActiveSupport::TimeZone["America/Los_Angeles"].local(2026, 6, 11, 12)
    @user.health_metrics.create!(metric_name: "weight", value: 61.2, units: "kg", recorded_at: noon_pt)
    @user.health_metrics.create!(metric_name: "active_energy", value: 500, units: "kcal", recorded_at: noon_pt)
    @user.health_metrics.create!(metric_name: "basal_energy_burned", value: 1300, units: "kcal", recorded_at: noon_pt)
    food = @user.foods.create!(description: "test food", kcal: 1, protein: 0, carbs: 0, fat: 0, fibre: 0)
    @user.food_logs.create!(food: food, consumed_at: noon_pt, kcal: 1650, protein: 140, fat: 50, carbs: 160, fibre: 0, alcohol: 21)
  end

  teardown do
    ENV["TRAINING_WEEK1_START"] = @original_week1_start
    ENV["NOTION_DAILY_LOGS_DS_ID"] = @original_ds_id
  end

  test "creates page with generated title, date, day type, and data fields when none exists" do
    client = FakeNotionClient.new(query_results: [[]])
    result = Notion::DailyLogSync.call(@user, date: DATE, day_type: "Easy Run", client: client)

    assert result.success
    assert result.created
    props = client.creates.first[:properties]
    assert_equal "Thu Jun 11 (W6 D4) - Easy Run", props["Day"]["title"].first["text"]["content"]
    assert_equal "2026-06-11", props["Date"]["date"]["start"]
    assert_equal "Easy Run", props["Day Type"]["select"]["name"]
    assert_equal 61.2, props["Weight (kg)"]["number"]
    assert_equal 1800.0, props["Calories Burned"]["number"]
    assert_equal 1650.0, props["Calories Actual"]["number"]
    assert_equal(-150.0, props["Deficit"]["number"])
    assert_equal 1.5, props["Alcohol (drinks)"]["number"]  # 21g / 14 = 1.5
  end

  test "updates existing page without touching human-owned fields or title" do
    existing = {"id" => "page-1", "properties" => {"Day Type" => {"select" => {"name" => "Rest"}}}}
    client = FakeNotionClient.new(query_results: [[existing]])

    result = Notion::DailyLogSync.call(@user, date: DATE, day_type: "Long Run", client: client)

    assert result.success
    refute result.created
    update = client.updates.first
    assert_equal "page-1", update[:page_id]
    props = update[:properties]
    refute props.key?("Day")
    refute props.key?("Mood")
    refute props.key?("Notes")
    refute props.key?("Red Flags")
    assert_equal "Long Run", props["Day Type"]["select"]["name"] # Rest -> Long Run upgrade
  end

  test "does not downgrade or overwrite a human-set day type" do
    existing = {"id" => "page-1", "properties" => {"Day Type" => {"select" => {"name" => "Travel"}}}}
    client = FakeNotionClient.new(query_results: [[existing]])

    Notion::DailyLogSync.call(@user, date: DATE, day_type: "Easy Run", client: client)

    refute client.updates.first[:properties].key?("Day Type")
  end

  test "omits properties with no data" do
    client = FakeNotionClient.new(query_results: [[]])
    @user.health_metrics.delete_all
    @user.food_logs.delete_all

    Notion::DailyLogSync.call(@user, date: DATE, client: client)

    props = client.creates.first[:properties]
    refute props.key?("Weight (kg)")
    refute props.key?("Deficit")
  end

  test "returns failure result on client error" do
    client = FakeNotionClient.new
    def client.query_data_source(*) = raise(Notion::Client::Error, "boom")

    result = Notion::DailyLogSync.call(@user, date: DATE, client: client)

    refute result.success
    assert_match "boom", result.error
  end
end
