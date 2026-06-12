require "net/http"

module Notion
  class Client
    Error = Class.new(StandardError)

    BASE_URL = "https://api.notion.com/v1"
    API_VERSION = "2025-09-03"

    def initialize(token: ENV.fetch("NOTION_API_TOKEN"))
      @token = token
    end

    def query_data_source(data_source_id, filter: nil)
      results = []
      cursor = nil
      loop do
        body = {}
        body["filter"] = filter if filter
        body["start_cursor"] = cursor if cursor
        response = request(:post, "/data_sources/#{data_source_id}/query", body)
        results.concat(response["results"])
        break unless response["has_more"]
        cursor = response["next_cursor"]
      end
      results
    end

    def create_page(data_source_id:, properties:, children: nil)
      body = {
        "parent" => {"type" => "data_source_id", "data_source_id" => data_source_id},
        "properties" => properties
      }
      body["children"] = children if children
      request(:post, "/pages", body)
    end

    def update_page(page_id, properties:)
      request(:patch, "/pages/#{page_id}", {"properties" => properties})
    end

    def append_blocks(page_id, children:)
      request(:patch, "/blocks/#{page_id}/children", {"children" => children})
    end

    private

    def request(method, path, body)
      uri = URI("#{BASE_URL}#{path}")
      request_class = (method == :post) ? Net::HTTP::Post : Net::HTTP::Patch
      req = request_class.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Notion-Version"] = API_VERSION
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      parsed = JSON.parse(response.body)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Notion API #{response.code} on #{method.to_s.upcase} #{path}: #{parsed["message"]}"
      end
      parsed
    end
  end
end
