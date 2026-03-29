require "test_helper"

class PlanAdherenceGeneratorTest < ActiveSupport::TestCase
  setup do
    @plan = plans(:with_content)
    @fake_response = Data.define(:content).new(content: "7-day: You ran twice. 30-day: Solid consistency.")
  end

  test "generates adherence summary and caches it on the plan" do
    stub_llm_chat(@fake_response) do
      result = PlanAdherenceGenerator.call(@plan)

      assert result.success
      assert_equal @fake_response.content, result.summary
      assert_equal @fake_response.content, @plan.reload.adherence_summary
      assert_not_nil @plan.adherence_summary_generated_at
    end
  end

  test "returns error on LLM failure without changing the plan" do
    stub_llm_chat_error("API timeout") do
      result = PlanAdherenceGenerator.call(@plan)

      assert_not result.success
      assert_equal "API timeout", result.error
      assert_nil @plan.reload.adherence_summary
    end
  end

  test "includes plan content and workout data in the context" do
    Workout.create!(
      external_id: "adherence-test",
      workout_type: "Running",
      started_at: 2.days.ago,
      ended_at: 2.days.ago + 30.minutes,
      duration: 1800,
      energy_burned: 300
    )

    captured_prompt = nil

    stub_llm_chat(@fake_response, capture: ->(prompt) { captured_prompt = prompt }) do
      PlanAdherenceGenerator.call(@plan)
    end

    assert_includes captured_prompt, @plan.content
    assert_includes captured_prompt, "Running"
    assert_includes captured_prompt, "Last 7 Days"
    assert_includes captured_prompt, "Last 30 Days"
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
