require "test_helper"

class PlanChatServiceTest < ActiveSupport::TestCase
  setup do
    @plan = plans(:with_content)
  end

  test "updates plan content and returns explanation" do
    llm_response = "Run 4x/week, strength 2x/week, rest on Sunday.\n---\nIncreased running from 3x to 4x per week as requested."

    stub_llm_chat(llm_response) do
      result = PlanChatService.call(@plan, "I want to run 4 times per week")

      assert result.success
      assert_equal "Increased running from 3x to 4x per week as requested.", result.response
      assert_equal "Run 4x/week, strength 2x/week, rest on Sunday.", @plan.reload.content
    end
  end

  test "handles response without separator" do
    llm_response = "Run 3x/week with one long run on weekends."

    stub_llm_chat(llm_response) do
      result = PlanChatService.call(@plan, "Simplify my plan")

      assert result.success
      assert_equal "Plan updated.", result.response
      assert_equal "Run 3x/week with one long run on weekends.", @plan.reload.content
    end
  end

  test "returns error on LLM failure without changing the plan" do
    original_content = @plan.content

    stub_llm_chat_error("API timeout") do
      result = PlanChatService.call(@plan, "Change something")

      assert_not result.success
      assert_equal "API timeout", result.error
      assert_equal original_content, @plan.reload.content
    end
  end

  test "works with a blank plan" do
    blank_plan = plans(:blank)
    llm_response = "Run 3x/week: Mon, Wed, Fri.\n---\nCreated a simple running plan."

    captured_prompt = nil

    stub_llm_chat(llm_response, capture: ->(prompt) { captured_prompt = prompt }) do
      result = PlanChatService.call(blank_plan, "I want to start running")

      assert result.success
      assert_equal "Run 3x/week: Mon, Wed, Fri.", blank_plan.reload.content
    end

    assert_includes captured_prompt, "No plan yet"
  end

  private

  def stub_llm_chat(response_text, capture: nil)
    fake_response = Data.define(:content).new(content: response_text)
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_instructions) { |_| self }
    fake_chat.define_singleton_method(:ask) { |prompt|
      capture&.call(prompt)
      fake_response
    }

    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }
    yield
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end

  def stub_llm_chat_error(message)
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| raise message }
    yield
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end
end
