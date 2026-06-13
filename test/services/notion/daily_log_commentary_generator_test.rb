require "test_helper"
require_relative "fake_notion_client"
require_relative "../../support/llm_stubbing"

class Notion::DailyLogCommentaryGeneratorTest < ActiveSupport::TestCase
  include LlmStubbing

  DATE = Date.new(2026, 6, 12)

  setup do
    @orig_llm_model = ENV["LLM_MODEL"]
    @orig_notion_api_token = ENV["NOTION_API_TOKEN"]
    @orig_training_week1_start = ENV["TRAINING_WEEK1_START"]
    @orig_notion_daily_logs_ds_id = ENV["NOTION_DAILY_LOGS_DS_ID"]

    ENV["LLM_MODEL"] = "gpt-5-nano"
    ENV["NOTION_API_TOKEN"] = "test-token"
    ENV["TRAINING_WEEK1_START"] = "2026-05-04"
    ENV["NOTION_DAILY_LOGS_DS_ID"] = "ds-daily"

    @user = users(:one)
    @fake_response = Data.define(:content).new(content: "Today was a solid training day.")
  end

  teardown do
    ENV["LLM_MODEL"] = @orig_llm_model
    ENV["NOTION_API_TOKEN"] = @orig_notion_api_token
    ENV["TRAINING_WEEK1_START"] = @orig_training_week1_start
    ENV["NOTION_DAILY_LOGS_DS_ID"] = @orig_notion_daily_logs_ds_id
  end

  def existing_page(id: "page-daily-1", red_flags: [])
    flag_data = red_flags.map { |f| {"name" => f} }
    {
      "id" => id,
      "properties" => {
        "Red Flags" => {"multi_select" => flag_data},
        "Notes" => {"rich_text" => []}
      }
    }
  end

  # (a) writes Notes with LLM text and merges red flags
  test "writes Notes with LLM narrative and merges existing and computed red flags" do
    # Page exists with existing human flag "Low mood"
    page = existing_page(red_flags: ["Low mood"])
    client = FakeNotionClient.new(query_results: [[page]])

    # Seed RHR data so RedFlagDetector computes "RHR up"
    tz = ActiveSupport::TimeZone["America/Los_Angeles"]
    (1..3).each do |i|
      @user.health_metrics.create!(
        metric_name: "resting_heart_rate", value: 50, units: "bpm",
        recorded_at: tz.local(DATE.year, DATE.month, DATE.day, 12) - i.days
      )
    end
    @user.health_metrics.create!(
      metric_name: "resting_heart_rate", value: 55, units: "bpm",
      recorded_at: tz.local(DATE.year, DATE.month, DATE.day, 12)
    )

    stub_llm_chat(@fake_response) do
      result = Notion::DailyLogCommentaryGenerator.call(@user, date: DATE, client: client)

      assert result.success
      assert_equal "Today was a solid training day.", result.narrative
      assert_equal 1, client.updates.size

      update = client.updates.first
      assert_equal "page-daily-1", update[:page_id]

      # Notes contains LLM text
      notes_content = update[:properties]["Notes"]["rich_text"].first["text"]["content"]
      assert_equal "Today was a solid training day.", notes_content

      # Red Flags merges both "Low mood" (existing) and "RHR up" (computed)
      flag_names = update[:properties]["Red Flags"]["multi_select"].map { |f| f["name"] }
      assert_includes flag_names, "Low mood"
      assert_includes flag_names, "RHR up"
    end
  end

  # (b) never removes existing flags
  test "never removes existing flags even when computed flags are empty" do
    page = existing_page(red_flags: ["Low mood", "Sleep <6.5h"])
    client = FakeNotionClient.new(query_results: [[page]])

    # No health metrics → no computed flags
    stub_llm_chat(@fake_response) do
      result = Notion::DailyLogCommentaryGenerator.call(@user, date: DATE, client: client)

      assert result.success
      update = client.updates.first

      # Red Flags should retain existing flags (merged = same as existing, so may not be in payload)
      # The implementation skips the Red Flags key when merged == existing.sort
      # Let's verify either Red Flags is absent (no-op) or still contains both flags.
      if update[:properties].key?("Red Flags")
        flag_names = update[:properties]["Red Flags"]["multi_select"].map { |f| f["name"] }
        assert_includes flag_names, "Low mood"
        assert_includes flag_names, "Sleep <6.5h"
      end
      # Either way, the Notes should still be written
      assert update[:properties].key?("Notes")
    end
  end

  # (c) creates the daily page first when missing
  test "creates the daily page via DailyLogSync when page is missing then writes to it" do
    # First query returns empty (page missing), after DailyLogSync creates it, second query returns it
    created_page = existing_page(id: "created-1", red_flags: [])
    client = FakeNotionClient.new(query_results: [[], [created_page]])

    # Stub DailyLogSync.call to simulate page creation
    orig_call = Notion::DailyLogSync.method(:call)
    Notion::DailyLogSync.define_singleton_method(:call) do |user, date:, client:|
      Notion::DailyLogSync::Result.new(success: true, page_id: "created-1", created: true)
    end

    stub_llm_chat(@fake_response) do
      result = Notion::DailyLogCommentaryGenerator.call(@user, date: DATE, client: client)

      assert result.success
      assert_equal 1, client.updates.size
      assert_equal "created-1", client.updates.first[:page_id]
    end
  ensure
    Notion::DailyLogSync.define_singleton_method(:call, orig_call)
  end

  # (d) LLM failure → no update call, success false
  test "LLM failure returns success false and makes no update_page call" do
    page = existing_page
    client = FakeNotionClient.new(query_results: [[page]])

    stub_llm_chat_error("LLM timeout") do
      result = Notion::DailyLogCommentaryGenerator.call(@user, date: DATE, client: client)

      refute result.success
      assert_equal "LLM timeout", result.error
      assert_empty client.updates
    end
  end

  # Red Flags not included in payload when merged == existing (no-op churn avoidance)
  test "omits Red Flags from payload when computed flags add nothing new" do
    page = existing_page(red_flags: [])
    client = FakeNotionClient.new(query_results: [[page]])

    # No health metrics → no computed flags; existing also empty → merged == existing, no churn
    stub_llm_chat(@fake_response) do
      Notion::DailyLogCommentaryGenerator.call(@user, date: DATE, client: client)
    end

    update = client.updates.first
    # Notes should still be written, Red Flags should NOT be in payload (no-op)
    assert update[:properties].key?("Notes")
    refute update[:properties].key?("Red Flags")
  end
end
