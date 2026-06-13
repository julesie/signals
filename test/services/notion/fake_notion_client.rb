class FakeNotionClient
  attr_reader :queries, :creates, :updates, :appends

  def initialize(query_results: [])
    @query_results = query_results # array of arrays, shifted per call
    @queries = []
    @creates = []
    @updates = []
    @appends = []
  end

  def query_data_source(ds_id, filter: nil)
    @queries << {ds_id: ds_id, filter: filter}
    @query_results.shift || []
  end

  def create_page(data_source_id:, properties:, children: nil)
    @creates << {ds_id: data_source_id, properties: properties, children: children}
    {"id" => "created-#{@creates.size}", "properties" => properties}
  end

  def update_page(page_id, properties:)
    @updates << {page_id: page_id, properties: properties}
    {"id" => page_id}
  end

  def append_blocks(page_id, children:)
    @appends << {page_id: page_id, children: children}
    {"results" => []}
  end
end
