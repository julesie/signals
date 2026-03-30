require "test_helper"

class NutritionProfilesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "edit renders form with current targets" do
    get edit_nutrition_profile_path
    assert_response :success
    assert_select "input[name='nutrition_profile[calorie_target]']"
    assert_select "input[name='nutrition_profile[protein_target]']"
  end

  test "edit creates profile if none exists" do
    user_without_profile = users(:two)
    sign_in user_without_profile

    assert_nil user_without_profile.nutrition_profile

    get edit_nutrition_profile_path
    assert_response :success
    assert user_without_profile.reload.nutrition_profile.present?
  end

  test "update saves new targets" do
    patch nutrition_profile_path, params: {nutrition_profile: {calorie_target: 2000, protein_target: 150}}
    assert_redirected_to food_logs_path

    profile = @user.nutrition_profile.reload
    assert_equal 2000, profile.calorie_target
    assert_equal 150, profile.protein_target
  end

  test "update rejects invalid targets" do
    patch nutrition_profile_path, params: {nutrition_profile: {calorie_target: 0}}
    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    sign_out @user
    get edit_nutrition_profile_path
    assert_response :redirect
  end
end
