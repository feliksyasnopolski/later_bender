class SemanticIndexer
  INDEX = SemanticChunksIndex.index_name

  def self.call(record, embedding_client: EmbeddingClient.new, client: SemanticChunksIndex.client)
    new(record, embedding_client:, client:).call
  end

  def self.rebuild!(records: SearchDocuments.all, embedding_client: EmbeddingClient.new, client: SemanticChunksIndex.client)
    records.each { |record| call(record, embedding_client:, client:) }
  end

  def initialize(record, embedding_client:, client:)
    @record = record
    @embedding_client = embedding_client
    @client = client
  end

  def call
    if @record.destroyed?
      delete_parent_chunks
      return
    end
    chunks = SemanticChunker.for(@record)
    if chunks.empty?
      delete_parent_chunks
      return
    end
    vectors = @embedding_client.embed(chunks, mode: :document)
    delete_parent_chunks
    body = chunks.each_with_index.map do |text, index|
      { index: { _index: INDEX, _id: chunk_id(index), data: document(text, vectors.fetch(index), index) } }
    end
    @client.bulk(body:, refresh: true)
  end

  private

  def parent_key
    "#{@record.class.name.underscore}-#{@record.id}"
  end

  def chunk_id(index)
    "#{parent_key}-#{index}"
  end

  def delete_parent_chunks
    @client.delete_by_query(index: INDEX, refresh: true, body: { query: { bool: { filter: [ { term: { kind: (@record.is_a?(StoredFile) ? "file" : @record.class.name.underscore) } }, { term: { parent_id: @record.id } } ] } } })
  rescue Elasticsearch::API::NotFound
    nil
  end

  def document(text, vector, index)
    project = @record.project
      { kind: @record.is_a?(StoredFile) ? "file" : @record.class.name.underscore, parent_id: @record.id, ref: (@record.ref if @record.is_a?(Task) || @record.is_a?(StoredFile)), number: (@record.number if @record.is_a?(Task) || @record.is_a?(StoredFile)), chunk_index: index, chunk_text: text, vector:, user_id: (project&.user_id || @record.user_id), project_id: @record.project_id, project_slug: project&.slug, project_name: project&.name, project_shorthand: project&.shorthand, tags: @record.tags.map(&:name), title: @record.is_a?(StoredFile) ? @record.filename : @record.title, created_at: @record.created_at, updated_at: @record.updated_at }.tap do |data|
      if @record.is_a?(StoredFile)
        representation = @record.searchable_representation
        data[:representation] = representation&.kind
        content = representation&.content.to_s
        start_line = content[0, content.index(text).to_i].to_s.lines.length + 1
        data[:locator] = { "kind" => representation&.metadata&.fetch("coordinate", "lines"), "start" => start_line, "end" => [ start_line + text.lines.length - 1, content.lines.length ].min }
        data[:filename] = @record.filename
        data[:media_type] = @record.media_type
      end
      data[:status] = @record.status if @record.is_a?(Task)
      data[:priority] = @record.priority if @record.is_a?(Task)
    end
  end
end
