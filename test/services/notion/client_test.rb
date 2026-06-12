require "test_helper"

class Notion::ClientTest < ActiveSupport::TestCase
  setup do
    @client = Notion::Client.new(token: "secret")
    @calls = []
    calls = @calls
    @responses = []
    responses = @responses
    @client.define_singleton_method(:request) do |method, path, body|
      calls << [method, path, body]
      responses.shift || {"results" => [], "has_more" => false}
    end
  end

  test "query_data_source posts filter and paginates" do
    @responses << {"results" => [{"id" => "p1"}], "has_more" => true, "next_cursor" => "abc"}
    @responses << {"results" => [{"id" => "p2"}], "has_more" => false}

    filter = {"property" => "Date", "date" => {"equals" => "2026-06-12"}}
    results = @client.query_data_source("ds-1", filter: filter)

    assert_equal %w[p1 p2], results.map { |r| r["id"] }
    assert_equal [:post, "/data_sources/ds-1/query", {"filter" => filter}], @calls[0]
    assert_equal "abc", @calls[1][2]["start_cursor"]
  end

  test "create_page targets data source parent and includes children when given" do
    @responses << {"id" => "new-page"}
    @client.create_page(data_source_id: "ds-1", properties: {"Day" => {}}, children: [{"type" => "paragraph"}])

    method, path, body = @calls[0]
    assert_equal :post, method
    assert_equal "/pages", path
    assert_equal({"type" => "data_source_id", "data_source_id" => "ds-1"}, body["parent"])
    assert body.key?("children")
  end

  test "update_page patches properties" do
    @responses << {"id" => "p1"}
    @client.update_page("p1", properties: {"RHR" => {"number" => 52}})
    assert_equal [:patch, "/pages/p1", {"properties" => {"RHR" => {"number" => 52}}}], @calls[0]
  end

  test "append_blocks patches block children" do
    @responses << {"results" => []}
    @client.append_blocks("p1", children: [{"type" => "paragraph"}])
    assert_equal :patch, @calls[0][0]
    assert_equal "/blocks/p1/children", @calls[0][1]
  end
end
