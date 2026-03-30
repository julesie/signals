require "test_helper"

class FoodLogsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  # -- new --

  test "new renders log form" do
    get new_food_log_path
    assert_response :success
    assert_select "textarea[name='description']"
    assert_select "select[name='mealtime']"
    assert_select "select[name='consumed_at_hour']"
  end

  test "new shows recent and frequent foods when data exists" do
    get new_food_log_path
    assert_response :success
  end

  test "new prefills description from param" do
    get new_food_log_path(prefill: "Eggs on toast")
    assert_response :success
    assert_match "Eggs on toast", response.body
  end

  # -- create (LLM estimation) --

  test "create estimates macros and saves food log" do
    llm_response = '{"kcal": 300, "protein": 25.0, "carbs": 20.0, "fat": 12.0, "fibre": 2.0, "alcohol": 0.0}'

    stub_llm_chat(llm_response) do
      assert_difference ["Food.count", "FoodLog.count"], 1 do
        post food_logs_path, params: {description: "Grilled chicken wrap", mealtime: "lunch", consumed_at_hour: 13}
      end
    end

    log = @user.food_logs.last
    assert_redirected_to food_logs_path(date: log.consumed_at.to_date)
    follow_redirect!
    assert_match "Grilled chicken wrap logged", response.body
    assert_equal "lunch", log.mealtime
    assert_equal 300.0, log.kcal.to_f
    assert_equal 25.0, log.protein.to_f
  end

  test "create shows error on LLM failure" do
    stub_llm_chat_error("API timeout") do
      assert_no_difference ["Food.count", "FoodLog.count"] do
        post food_logs_path, params: {description: "Mystery food", mealtime: "dinner"}
      end
    end

    assert_redirected_to new_food_log_path
    follow_redirect!
    assert_match "Could not estimate", response.body
  end

  # -- quick_add --

  test "quick_add clones food as new log" do
    food = foods(:eggs_on_toast)

    assert_difference "FoodLog.count", 1 do
      post quick_add_food_log_path(food_id: food.id)
    end

    log = @user.food_logs.order(created_at: :desc).first
    assert_redirected_to food_logs_path(date: log.consumed_at.to_date)
    assert_equal food.id, log.food_id
    assert_equal food.kcal, log.kcal
    assert_equal food.protein, log.protein
  end

  # -- destroy --

  test "destroy removes food log" do
    log = food_logs(:breakfast_eggs)

    assert_difference "FoodLog.count", -1 do
      delete food_log_path(log)
    end

    assert_redirected_to food_logs_path(date: log.consumed_at.to_date)
  end

  # -- index (daily view) --

  test "index shows today's food logs grouped by mealtime" do
    get food_logs_path
    assert_response :success
    assert_match "Today", response.body
    assert_match "breakfast", response.body
    assert_match "Two eggs on toast", response.body
    assert_match "lunch", response.body
  end

  test "index shows progress bars" do
    get food_logs_path
    assert_response :success
    assert_match "kcal", response.body
    assert_match "Protein", response.body
  end

  test "index filters by date param" do
    get food_logs_path(date: 1.day.ago.to_date)
    assert_response :success
  end

  test "index shows empty state when no logs" do
    get food_logs_path(date: 1.year.ago.to_date)
    assert_response :success
    assert_match "No food logged", response.body
  end

  # -- edit --

  test "edit renders form with current values" do
    log = food_logs(:breakfast_eggs)
    get edit_food_log_path(log)
    assert_response :success
    assert_select "input[name='food_log[kcal]']"
    assert_select "input[name='food_log[protein]']"
  end

  # -- update --

  test "update saves changes to food log and food" do
    log = food_logs(:breakfast_eggs)
    food = log.food

    patch food_log_path(log), params: {
      food_log: {mealtime: "snack", kcal: 400, protein: 25.0, carbs: 35.0, fat: 20.0, fibre: 3.0, alcohol: 0.0, consumed_at_hour: 10}
    }

    assert_redirected_to food_logs_path(date: log.consumed_at.to_date)

    log.reload
    assert_equal "snack", log.mealtime
    assert_equal 400.0, log.kcal.to_f
    assert_equal 25.0, log.protein.to_f

    food.reload
    assert_equal 400.0, food.kcal.to_f
    assert_equal 25.0, food.protein.to_f
  end

  # -- auth --

  test "requires authentication" do
    sign_out @user
    get new_food_log_path
    assert_response :redirect
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
