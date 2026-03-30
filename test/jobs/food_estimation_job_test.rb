require "test_helper"

class FoodEstimationJobTest < ActiveSupport::TestCase
  setup do
    @food = foods(:eggs_on_toast)
    @log = food_logs(:breakfast_eggs)
    @log.update!(estimated: false, kcal: 0, protein: 0, carbs: 0, fat: 0, fibre: 0, alcohol: 0)
  end

  test "updates food and food_log with estimated macros" do
    llm_response = '{"kcal": 350, "protein": 20.0, "carbs": 30.0, "fat": 18.0, "fibre": 2.0, "alcohol": 0.0}'

    stub_llm_chat(llm_response) do
      FoodEstimationJob.perform_now(@log.id)
    end

    @log.reload
    assert @log.estimated?
    assert_equal 350.0, @log.kcal.to_f
    assert_equal 20.0, @log.protein.to_f

    @food.reload
    assert_equal 350.0, @food.kcal.to_f
    assert_equal 20.0, @food.protein.to_f
  end

  test "marks as estimated even on LLM failure" do
    stub_llm_chat_error("API timeout") do
      FoodEstimationJob.perform_now(@log.id)
    end

    @log.reload
    assert @log.estimated?
    assert_equal 0, @log.kcal.to_i
  end

  private

  def stub_llm_chat(response_text)
    fake_response = Data.define(:content).new(content: response_text)
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_instructions) { |_| self }
    fake_chat.define_singleton_method(:ask) { |_| fake_response }

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
