require "test_helper"

class PlanSuggestionGeneratorTest < ActiveSupport::TestCase
  setup do
    @plan = plans(:with_content)
    @fake_response = Data.define(:content).new(content: "Go for a 5K easy run today.")
  end

  test "generates a suggestion and caches it on the plan" do
    stub_llm_chat(@fake_response) do
      result = PlanSuggestionGenerator.call(@plan)

      assert result.success
      assert_equal "Go for a 5K easy run today.", result.suggestion
      assert_equal "Go for a 5K easy run today.", @plan.reload.daily_suggestion
      assert_not_nil @plan.suggestion_generated_at
    end
  end

  test "returns error on LLM failure without changing the plan" do
    original_suggestion = @plan.daily_suggestion

    stub_llm_chat_error("API timeout") do
      result = PlanSuggestionGenerator.call(@plan)

      assert_not result.success
      assert_equal "API timeout", result.error
      assert_equal original_suggestion, @plan.reload.daily_suggestion
    end
  end

  test "includes plan content and today's date in the context" do
    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanSuggestionGenerator.call(@plan)
    end

    assert_includes captured_prompt, @plan.content
    assert_includes captured_prompt, Date.current.strftime("%A, %B %-d, %Y")
  end

  test "includes recent workouts in the context" do
    Workout.create!(
      external_id: "test-workout-suggestion",
      workout_type: "Running",
      started_at: 2.days.ago,
      ended_at: 2.days.ago + 45.minutes,
      duration: 2700,
      distance: 6.2,
      distance_units: "km",
      energy_burned: 420
    )

    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanSuggestionGenerator.call(@plan)
    end

    assert_includes captured_prompt, "Running"
    assert_includes captured_prompt, "6.2 km"
  end

  private

  def stub_llm_chat(response, capture: nil, &block)
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_params) { |**_| self }
    fake_chat.define_singleton_method(:with_instructions) { |_| self }
    fake_chat.define_singleton_method(:ask) { |prompt|
      capture&.call(prompt)
      response
    }

    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }
    yield
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end

  def stub_llm_chat_error(message, &block)
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| raise message }
    yield
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end
end
