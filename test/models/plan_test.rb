require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "belongs to user" do
    plan = plans(:with_content)
    assert_equal users(:one), plan.user
  end

  test "enforces one plan per user" do
    duplicate = Plan.new(user: users(:one))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "has_content? returns true when content is present" do
    assert plans(:with_content).has_content?
  end

  test "has_content? returns false when content is blank" do
    assert_not plans(:blank).has_content?
  end

  test "has_suggestion? returns true when suggestion is present" do
    assert plans(:with_content).has_suggestion?
  end

  test "has_suggestion? returns false when suggestion is blank" do
    assert_not plans(:blank).has_suggestion?
  end

  test "user has_one plan" do
    assert_equal plans(:with_content), users(:one).plan
  end
end
