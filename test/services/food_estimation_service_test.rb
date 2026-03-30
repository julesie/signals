require "test_helper"

class FoodEstimationServiceTest < ActiveSupport::TestCase
  test "returns macros from valid LLM response" do
    llm_response = '{"kcal": 350, "protein": 20.0, "carbs": 30.0, "fat": 18.0, "fibre": 2.0, "alcohol": 0.0}'

    stub_llm_chat(llm_response) do
      result = FoodEstimationService.call("Two eggs on toast with butter")

      assert result.success
      assert_equal 350.0, result.macros["kcal"]
      assert_equal 20.0, result.macros["protein"]
      assert_equal 30.0, result.macros["carbs"]
      assert_equal 18.0, result.macros["fat"]
      assert_equal 2.0, result.macros["fibre"]
      assert_equal 0.0, result.macros["alcohol"]
    end
  end

  test "handles markdown code fenced JSON" do
    llm_response = "```json\n{\"kcal\": 200, \"protein\": 15.0, \"carbs\": 10.0, \"fat\": 8.0, \"fibre\": 1.0, \"alcohol\": 0.0}\n```"

    stub_llm_chat(llm_response) do
      result = FoodEstimationService.call("Scrambled eggs")

      assert result.success
      assert_equal 200.0, result.macros["kcal"]
    end
  end

  test "returns error on missing keys" do
    llm_response = '{"kcal": 100, "protein": 10.0}'

    stub_llm_chat(llm_response) do
      result = FoodEstimationService.call("Something")

      assert_not result.success
      assert_match(/Missing keys/, result.error)
    end
  end

  test "returns error on invalid JSON" do
    llm_response = "I think that's about 300 calories"

    stub_llm_chat(llm_response) do
      result = FoodEstimationService.call("A sandwich")

      assert_not result.success
      assert result.error.present?
    end
  end

  test "returns error on LLM failure" do
    stub_llm_chat_error("API timeout") do
      result = FoodEstimationService.call("Chicken salad")

      assert_not result.success
      assert_equal "API timeout", result.error
    end
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
