require "test_helper"

class NutritionProfileTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
  end

  test "valid with required fields" do
    profile = @user.build_nutrition_profile(calorie_target: 2000, protein_target: 150)
    assert profile.valid?
  end

  test "invalid without calorie_target" do
    profile = @user.build_nutrition_profile(calorie_target: nil, protein_target: 100)
    assert_not profile.valid?
  end

  test "invalid without protein_target" do
    profile = @user.build_nutrition_profile(calorie_target: 1600, protein_target: nil)
    assert_not profile.valid?
  end

  test "invalid with zero calorie_target" do
    profile = @user.build_nutrition_profile(calorie_target: 0, protein_target: 100)
    assert_not profile.valid?
  end

  test "invalid with negative protein_target" do
    profile = @user.build_nutrition_profile(calorie_target: 1600, protein_target: -10)
    assert_not profile.valid?
  end

  test "enforces one profile per user" do
    NutritionProfile.create!(user: @user, calorie_target: 1600, protein_target: 100)
    duplicate = NutritionProfile.new(user: @user, calorie_target: 2000, protein_target: 150)
    assert_not duplicate.valid?
  end

  test "defaults from migration" do
    profile = NutritionProfile.new(user: @user)
    assert_equal 1600, profile.calorie_target
    assert_equal 100, profile.protein_target
  end
end
