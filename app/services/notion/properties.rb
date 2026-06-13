module Notion
  module Properties
    TEXT_LIMIT = 2000

    module_function

    def title(text) = {"title" => [{"text" => {"content" => text.to_s[0, TEXT_LIMIT]}}]}

    def rich_text(text) = {"rich_text" => [{"text" => {"content" => text.to_s[0, TEXT_LIMIT]}}]}

    def number(value) = {"number" => value&.to_f}

    def date(d) = {"date" => {"start" => d.iso8601}}

    def select(name) = {"select" => {"name" => name}}

    def multi_select(names) = {"multi_select" => names.map { |n| {"name" => n} }}

    def checkbox(value) = {"checkbox" => !!value}

    def paragraph_block(text)
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => {"rich_text" => [{"text" => {"content" => text.to_s[0, TEXT_LIMIT]}}]}
      }
    end

    def read_select(prop) = prop&.dig("select", "name")

    def read_multi_select(prop) = Array(prop&.dig("multi_select")).map { |o| o["name"] }

    def read_number(prop) = prop&.dig("number")

    def read_title(prop) = Array(prop&.dig("title")).map { |t| t["plain_text"] }.join

    def read_date(prop) = prop&.dig("date", "start")
  end
end
