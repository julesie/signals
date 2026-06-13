require "test_helper"
require_relative "fake_notion_client"
require_relative "../../support/llm_stubbing"

class Notion::WorkoutCommentaryGeneratorTest < ActiveSupport::TestCase
  include LlmStubbing

  setup do
    @orig_llm_model = ENV["LLM_MODEL"]
    @orig_notion_api_token = ENV["NOTION_API_TOKEN"]
    ENV["LLM_MODEL"] = "gpt-5-nano"
    ENV["NOTION_API_TOKEN"] = "test-token"

    @user = users(:one)
    @plan = plans(:with_content) # belongs to users(:one) via fixture; the generator reaches it through workout.user.plan
    @fake_response = Data.define(:content).new(content: "Good steady effort today.")

    @workout = @user.workouts.create!(
      external_id: "commentary-test-#{SecureRandom.hex(4)}",
      workout_type: "Running",
      started_at: 1.day.ago,
      ended_at: 1.day.ago + 35.minutes,
      duration: 2100,
      distance: 5.0,
      distance_units: "km",
      energy_burned: 410,
      notion_page_id: "notion-page-abc",
      metadata: {"heartRate" => {"avg" => 152.3}}
    )
  end

  teardown do
    ENV["LLM_MODEL"] = @orig_llm_model
    ENV["NOTION_API_TOKEN"] = @orig_notion_api_token
  end

  test "success path appends one paragraph block containing LLM text to workout notion_page_id" do
    client = FakeNotionClient.new

    stub_llm_chat(@fake_response) do
      result = Notion::WorkoutCommentaryGenerator.call(@workout, client: client)

      assert result.success
      assert_equal "Good steady effort today.", result.commentary
      assert_equal 1, client.appends.size
      append = client.appends.first
      assert_equal "notion-page-abc", append[:page_id]
      block = append[:children].first
      assert_equal "paragraph", block["type"]
      assert_includes block.dig("paragraph", "rich_text", 0, "text", "content"), "Good steady effort today."
      assert_includes block.dig("paragraph", "rich_text", 0, "text", "content"), "🤖 Coach:"
    end
  end

  test "prompt includes workout type, distance, and plan content" do
    client = FakeNotionClient.new
    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      Notion::WorkoutCommentaryGenerator.call(@workout, client: client)
    end

    assert_includes captured_prompt, "Running"
    assert_includes captured_prompt, "5.0"
    assert_includes captured_prompt, @plan.content
  end

  test "LLM failure returns Result success false and makes no append_blocks call" do
    client = FakeNotionClient.new

    stub_llm_chat_error("LLM timeout") do
      result = Notion::WorkoutCommentaryGenerator.call(@workout, client: client)

      refute result.success
      assert_equal "LLM timeout", result.error
      assert_empty client.appends
    end
  end

  test "workout without notion_page_id returns failure with no API call and no LLM call" do
    @workout.update_column(:notion_page_id, nil)
    client = FakeNotionClient.new
    llm_called = false

    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_|
      llm_called = true
      raise "should not be called"
    }

    result = Notion::WorkoutCommentaryGenerator.call(@workout, client: client)

    refute result.success
    assert_match(/notion_page_id/, result.error)
    assert_empty client.appends
    refute llm_called
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end
end
