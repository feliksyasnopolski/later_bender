class SearchService
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 100
  KINDS = %w[task note].freeze

  def initialize(user:, q: nil, project: nil, kinds: nil, tags: nil, limit: nil)
    @user = user
    @q = q.to_s.strip
    @project = project.to_s.strip.presence
    @kinds = Array(kinds).map(&:to_s).intersection(KINDS)
    @tags = Array(tags).map { |tag| tag.to_s.strip.downcase }.reject(&:blank?).uniq
    @limit = [[limit.to_i, 1].max, MAX_LIMIT].min if limit.present?
    @limit ||= DEFAULT_LIMIT
  end

  def call
    request = SearchDocumentsIndex.all
    request = request.query(bool: { must: [keyword_query].compact, filter: filters })
    request = request.highlight(
      fields: %w[title context intended_direction body].to_h { |field| [field, { fragment_size: 240, number_of_fragments: 1 }] },
      pre_tags: ["<em>"],
      post_tags: ["</em>"]
    ) if @q.present?
    request.limit(@limit).to_a.map { |hit| result_for(hit) }
  end

  private

  def keyword_query
    return if @q.blank?

    { multi_match: {
      query: @q,
      fields: ["title^2", "tags^2", "intended_direction^2", "project_name^2", "context^1.5", "body^1.5"],
      type: "most_fields",
      fuzziness: "AUTO"
    } }
  end

  def filters
    filters = [{ term: { user_id: @user.id } }]
    filters << { term: { project_slug: @project } } if @project
    filters << { terms: { kind: @kinds } } if @kinds.present?
    @tags.each { |tag| filters << { term: { tags: tag } } }
    filters
  end

  def result_for(hit)
    {
      id: hit.id.to_i,
      kind: hit.kind,
      title: hit.title,
      project: hit.project_slug,
      tags: hit.tags || [],
      status: hit.status,
      priority: hit.priority,
      context: hit.context,
      intended_direction: hit.intended_direction,
      body: hit.body,
      related_note_ids: hit.related_note_ids || [],
      highlights: highlights_for(hit),
      created_at: hit.created_at,
      updated_at: hit.updated_at,
      score: hit._score
    }.compact
  end

  def highlights_for(hit)
    %w[title context intended_direction body].each_with_object({}) do |field, highlights|
      values = hit.public_send("#{field}_highlights")
      highlights[field] = values if values.present?
    end
  end
end
