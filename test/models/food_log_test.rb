require "test_helper"

class FoodLogTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @food = foods(:eggs_on_toast)
  end

  test "valid with required fields" do
    log = @user.food_logs.new(food: @food, consumed_at: Time.current, mealtime: "breakfast")
    assert log.valid?
  end

  test "invalid without consumed_at" do
    log = @user.food_logs.new(food: @food, mealtime: "breakfast")
    assert_not log.valid?
    assert_includes log.errors[:consumed_at], "can't be blank"
  end

  test "valid with nil mealtime" do
    log = @user.food_logs.new(food: @food, consumed_at: Time.current, mealtime: nil)
    assert log.valid?
  end

  test "invalid with unknown mealtime" do
    log = @user.food_logs.new(food: @food, consumed_at: Time.current, mealtime: "brunch")
    assert_not log.valid?
  end

  test "valid mealtimes" do
    %w[breakfast lunch dinner snack].each do |mealtime|
      log = @user.food_logs.new(food: @food, consumed_at: Time.current, mealtime: mealtime)
      assert log.valid?, "Expected #{mealtime} to be valid"
    end
  end

  test "on_date scope returns logs for given date" do
    logs = FoodLog.on_date(Date.current)
    assert logs.any?
    logs.each do |log|
      assert_equal Date.current, log.consumed_at.to_date
    end
  end

  test "by_mealtime scope filters correctly" do
    breakfast_logs = @user.food_logs.by_mealtime("breakfast")
    breakfast_logs.each do |log|
      assert_equal "breakfast", log.mealtime
    end
  end

  test "stamp_macros_from_food copies all macro fields" do
    log = @user.food_logs.new(food: @food, consumed_at: Time.current)
    log.stamp_macros_from_food!

    assert_equal @food.kcal, log.kcal
    assert_equal @food.protein, log.protein
    assert_equal @food.carbs, log.carbs
    assert_equal @food.fat, log.fat
    assert_equal @food.fibre, log.fibre
    assert_equal @food.alcohol, log.alcohol
  end

  test "net_carbs computes carbs minus fibre" do
    log = food_logs(:lunch_chicken)
    assert_equal 42.0, log.net_carbs
  end

  test "default_mealtime returns based on time of day" do
    travel_to Time.current.change(hour: 7) do
      assert_equal "breakfast", FoodLog.default_mealtime
    end

    travel_to Time.current.change(hour: 12) do
      assert_equal "lunch", FoodLog.default_mealtime
    end

    travel_to Time.current.change(hour: 18) do
      assert_equal "dinner", FoodLog.default_mealtime
    end
  end
end
