require "test_helper"

class Notion::TrainingWeekTest < ActiveSupport::TestCase
  W1 = Date.new(2026, 5, 4) # Monday

  test "computes week and day numbers" do
    tw = Notion::TrainingWeek.new(Date.new(2026, 6, 11), week1_start: W1) # known: W6 D4
    assert_equal 6, tw.week_number
    assert_equal 4, tw.day_number
    assert_equal Date.new(2026, 6, 8), tw.week_start
    assert_equal "W6 D4", tw.label
  end

  test "first day of plan is W1 D1" do
    tw = Notion::TrainingWeek.new(W1, week1_start: W1)
    assert_equal "W1 D1", tw.label
  end

  test "daily log title format" do
    tw = Notion::TrainingWeek.new(Date.new(2026, 6, 11), week1_start: W1)
    assert_equal "Thu Jun 11 (W6 D4) - Rest", tw.daily_title("Rest")
  end

  test "today returns a date in Pacific time" do
    assert_instance_of Date, Notion::TrainingWeek.today
  end
end
