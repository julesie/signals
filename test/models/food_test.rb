require "test_helper"

class FoodTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "valid with all required fields" do
    food = @user.foods.new(
      description: "Chicken salad",
      kcal: 300, protein: 35.0, carbs: 10.0, fat: 12.0, fibre: 3.0
    )
    assert food.valid?
  end

  test "invalid without description" do
    food = @user.foods.new(kcal: 300, protein: 35.0, carbs: 10.0, fat: 12.0, fibre: 3.0)
    assert_not food.valid?
    assert_includes food.errors[:description], "can't be blank"
  end

  test "invalid without kcal" do
    food = @user.foods.new(description: "Chicken salad", protein: 35.0, carbs: 10.0, fat: 12.0, fibre: 3.0)
    assert_not food.valid?
    assert_includes food.errors[:kcal], "can't be blank"
  end

  test "invalid without protein" do
    food = @user.foods.new(description: "Test", kcal: 100, carbs: 10.0, fat: 5.0, fibre: 1.0)
    assert_not food.valid?
  end

  test "invalid without carbs" do
    food = @user.foods.new(description: "Test", kcal: 100, protein: 10.0, fat: 5.0, fibre: 1.0)
    assert_not food.valid?
  end

  test "invalid without fat" do
    food = @user.foods.new(description: "Test", kcal: 100, protein: 10.0, carbs: 10.0, fibre: 1.0)
    assert_not food.valid?
  end

  test "invalid without fibre" do
    food = @user.foods.new(description: "Test", kcal: 100, protein: 10.0, carbs: 10.0, fat: 5.0)
    assert_not food.valid?
  end

  test "alcohol defaults to zero" do
    food = @user.foods.create!(
      description: "Test food",
      kcal: 100, protein: 10.0, carbs: 10.0, fat: 5.0, fibre: 1.0
    )
    assert_equal 0, food.alcohol.to_i
  end

  test "net_carbs computes carbs minus fibre" do
    food = foods(:eggs_on_toast)
    assert_equal 28.0, food.net_carbs
  end

  test "destroying food destroys associated food_logs" do
    food = foods(:eggs_on_toast)
    assert_difference "FoodLog.count", -1 do
      food.destroy
    end
  end
end
