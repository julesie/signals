require "test_helper"

class Notion::PropertiesTest < ActiveSupport::TestCase
  test "builds title, rich_text, number, date, select, multi_select, checkbox" do
    assert_equal({"title" => [{"text" => {"content" => "Hi"}}]}, Notion::Properties.title("Hi"))
    assert_equal({"rich_text" => [{"text" => {"content" => "note"}}]}, Notion::Properties.rich_text("note"))
    assert_equal({"number" => 7.5}, Notion::Properties.number(7.5))
    assert_equal({"date" => {"start" => "2026-06-12"}}, Notion::Properties.date(Date.new(2026, 6, 12)))
    assert_equal({"select" => {"name" => "Easy Run"}}, Notion::Properties.select("Easy Run"))
    assert_equal({"multi_select" => [{"name" => "RHR up"}, {"name" => "HRV down"}]},
      Notion::Properties.multi_select(["RHR up", "HRV down"]))
    assert_equal({"checkbox" => true}, Notion::Properties.checkbox(true))
  end

  test "rich_text truncates to 2000 chars" do
    prop = Notion::Properties.rich_text("x" * 3000)
    assert_equal 2000, prop["rich_text"].first["text"]["content"].length
  end

  test "reads values from page property JSON" do
    assert_equal "Planned", Notion::Properties.read_select({"select" => {"name" => "Planned"}})
    assert_nil Notion::Properties.read_select({"select" => nil})
    assert_equal ["RHR up"], Notion::Properties.read_multi_select({"multi_select" => [{"name" => "RHR up"}]})
    assert_equal [], Notion::Properties.read_multi_select(nil)
    assert_equal 5.0, Notion::Properties.read_number({"number" => 5.0})
    assert_equal "W1 Fri - 5km Easy Run",
      Notion::Properties.read_title({"title" => [{"plain_text" => "W1 Fri - 5km Easy Run"}]})
    assert_equal "2026-06-12", Notion::Properties.read_date({"date" => {"start" => "2026-06-12"}})
  end

  test "paragraph_block builds a body block and truncates" do
    block = Notion::Properties.paragraph_block("hello")
    assert_equal "paragraph", block["type"]
    assert_equal "hello", block.dig("paragraph", "rich_text", 0, "text", "content")
  end
end
