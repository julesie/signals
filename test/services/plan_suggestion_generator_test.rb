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
    @plan.user.workouts.create!(
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

  test "includes today's completed workouts in the context" do
    @plan.user.workouts.create!(
      external_id: "today-strength",
      workout_type: "Traditional Strength Training",
      started_at: 3.hours.ago,
      ended_at: 2.hours.ago,
      duration: 2400,
      energy_burned: 350
    )

    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanSuggestionGenerator.call(@plan)
    end

    assert_includes captured_prompt, "Today's Completed Workouts"
    assert_includes captured_prompt, "Traditional Strength Training"
  end

  test "includes workout notes in the context when present" do
    @plan.user.workouts.create!(
      external_id: "noted-workout",
      workout_type: "Running",
      started_at: 2.days.ago,
      ended_at: 2.days.ago + 30.minutes,
      duration: 1800,
      notes: "Knee felt tight on hills"
    )

    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanSuggestionGenerator.call(@plan)
    end

    assert_includes captured_prompt, "Knee felt tight on hills"
  end

  test "includes today's workout notes in the context" do
    @plan.user.workouts.create!(
      external_id: "today-noted",
      workout_type: "Running",
      started_at: 1.hour.ago,
      ended_at: Time.current,
      duration: 1800,
      notes: "Easy recovery pace"
    )

    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanSuggestionGenerator.call(@plan)
    end

    assert_includes captured_prompt, "Easy recovery pace"
  end

  test "omits notes from context when not present" do
    @plan.user.workouts.create!(
      external_id: "no-note-workout",
      workout_type: "Running",
      started_at: 2.days.ago,
      ended_at: 2.days.ago + 30.minutes,
      duration: 1800
    )

    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanSuggestionGenerator.call(@plan)
    end

    refute_match(/— "/, captured_prompt)
  end

  test "context says no workouts today when none exist" do
    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanSuggestionGenerator.call(@plan)
    end

    assert_includes captured_prompt, "No workouts completed yet today"
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
