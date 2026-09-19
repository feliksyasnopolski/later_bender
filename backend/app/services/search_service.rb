class SearchService
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 100
  KINDS = %w[task note file].freeze
  RETRIEVAL_MULTIPLIER = 5

  def initialize(user:, q: nil, project: nil, scope: nil, kinds: nil, tags: nil, statuses: nil, priorities: nil, limit: nil, mode: :hybrid, embedding_client: EmbeddingClient.new, semantic_client: nil)
    @user, @q = user, q.to_s.strip
    @project = project.to_s.strip.presence
    @scope = scope.to_s.strip.presence
    @kinds = Array(kinds).flat_map { |kind| kind.to_s.split(",") }.intersection(KINDS)
    @tags = Array(tags).flat_map { |tag| tag.to_s.split(",") }.map { |tag| tag.strip.downcase }.reject(&:blank?).uniq
    @statuses = Array(statuses).flat_map { |status| status.to_s.split(",") }.intersection(Task::STATUSES)
    @priorities = Array(priorities).flat_map { |priority| priority.to_s.split(",") }.intersection(Task::PRIORITIES)
    @limit = [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min if limit.present?
    @limit ||= DEFAULT_LIMIT
    @mode, @embedding_client, @semantic_client = mode.to_sym, embedding_client, semantic_client
  end

  def call
    lexical = lexical_hits
    return lexical.first(@limit).map { |hit| result_for(hit) } if @mode == :lexical || @q.blank?
    semantic = semantic_hits
    return semantic_results(semantic) if @mode == :semantic

    lexical_by_id = lexical.index_by { |hit| "#{hit.kind}-#{hit.id}" }
    semantic_by_id = semantic.each_with_object({}) do |hit, by_id|
      id = "#{hit.fetch("kind")}-#{hit.fetch("parent_id")}"
      by_id[id] ||= hit
    end
    RrfFuser.call(lexical_by_id.keys, semantic_by_id.keys, limit: @limit).map do |id|
      lexical_by_id[id] ? result_for(lexical_by_id[id], fallback_snippet: semantic_by_id[id]&.fetch("chunk_text", nil)) : semantic_result_for(semantic_by_id.fetch(id))
    end
  rescue StandardError => e
    raise if %i[lexical semantic].include?(@mode)
    Rails.logger.warn("semantic search degraded to lexical: #{e.class}: #{e.message}")
    lexical_hits.first(@limit).map { |hit| result_for(hit) }
  end

  private

  def lexical_hits
    request = SearchDocumentsIndex.all.query(bool: { must: [ keyword_query ].compact, filter: filters })
    request = request.highlight(highlight_options) if @q.present?
    request.limit(@limit * RETRIEVAL_MULTIPLIER).to_a
  end

  def semantic_hits
    vector = @embedding_client.embed([ @q ], mode: :query).fetch(0)
    response = (@semantic_client || SemanticChunksIndex.client).search(index: SemanticIndexer::INDEX, body: { knn: { field: "vector", query_vector: vector, k: @limit * RETRIEVAL_MULTIPLIER, num_candidates: @limit * RETRIEVAL_MULTIPLIER * 10, filter: filters } })
    response.fetch("hits").fetch("hits").map { |hit| hit.fetch("_source").merge("_score" => hit["_score"]) }
  end

  def keyword_query
    return if @q.blank?
    { multi_match: { query: @q, fields: [ "title^2", "tags^2", "intended_direction^2", "project_name^2", "context^1.5", "body^1.5" ], type: "most_fields", fuzziness: "AUTO" } }
  end

  def filters
    values = [ { term: { user_id: @user.id } } ]
    values << { term: { project_slug: @project } } if @project
    values << { term: { kind: "note" } } if @scope == "global"
    values << { bool: { must_not: [ { exists: { field: "project_id" } } ] } } if @scope == "global"
    values << { terms: { kind: @kinds } } if @kinds.present?
    @tags.each { |tag| values << { term: { tags: tag } } }
    values << { terms: { status: @statuses } } if @statuses.present?
    values << { terms: { priority: @priorities } } if @priorities.present?
    values
  end

  def highlight_options
    { fields: %w[title context intended_direction body].to_h { |field| [ field, { fragment_size: 240, number_of_fragments: 1 } ] }, pre_tags: [ "" ], post_tags: [ "" ] }
  end

  def semantic_results(hits)
    hits.group_by { |hit| "#{hit.fetch("kind")}-#{hit.fetch("parent_id")}" }.values.map { |matches| semantic_result_for(matches.max_by { |hit| hit.fetch("_score", 0) }) }.first(@limit)
  end

  def result_for(hit, fallback_snippet: nil)
    { id: hit.id.to_i, ref: hit.ref, number: hit.number, kind: hit.kind, title: hit.title, filename: (hit.filename if hit.kind == "file"), media_type: (hit.media_type if hit.kind == "file"), project: hit.project_id && { id: hit.project_id.to_i, slug: hit.project_slug, name: hit.project_name, shorthand: hit.project_shorthand }, tags: hit.tags || [], status: hit.status, priority: hit.priority, snippet: snippet_for(hit, fallback_snippet), highlights: highlights_for(hit), created_at: hit.created_at, updated_at: hit.updated_at }.tap do |result|
      result.delete(:status) if hit.kind != "task"
      result.delete(:priority) if hit.kind != "task"
      result.delete(:filename) if hit.kind != "file"
      result.delete(:media_type) if hit.kind != "file"
      result[:match] = { representation: hit.representation, locator: hit.locator } if hit.kind == "file" && hit.respond_to?(:representation) && hit.representation.present?
    end
  end

  def semantic_result_for(hit)
    result = { id: hit.fetch("parent_id").to_i, ref: hit["ref"], number: hit["number"], kind: hit.fetch("kind"), title: hit.fetch("title"), filename: hit["filename"], media_type: hit["media_type"], project: hit["project_id"] && { id: hit.fetch("project_id").to_i, slug: hit["project_slug"], name: hit["project_name"], shorthand: hit["project_shorthand"] }, tags: hit["tags"] || [], snippet: hit.fetch("chunk_text").to_s.slice(0, 280), highlights: [], created_at: hit.fetch("created_at"), updated_at: hit.fetch("updated_at") }
    result[:status] = hit["status"] if result[:kind] == "task"
    result[:priority] = hit["priority"] if result[:kind] == "task"
    result[:match] = { representation: hit["representation"], locator: hit["locator"] } if result[:kind] == "file"
    result
  end

  def highlights_for(hit)
    %w[title context intended_direction body].each_with_object([]) do |field, highlights|
      values = hit.public_send("#{field}_highlights")
      highlights << { field: field, fragments: values } if values.present?
    end
  end

  def snippet_for(hit, fallback_snippet = nil)
    highlights_for(hit).first&.dig(:fragments, 0) || fallback_snippet.to_s.slice(0, 280).presence || hit.title.to_s
  end
end
