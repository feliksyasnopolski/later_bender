class SearchService
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 100
  KINDS = %w[task note].freeze

  def initialize(user:, q: nil, project: nil, scope: nil, kinds: nil, tags: nil, statuses: nil, priorities: nil, limit: nil)
    @user = user
    @q = q.to_s.strip
    @project = project.to_s.strip.presence
    @scope = scope.to_s.strip.presence
    @kinds = Array(kinds).flat_map { |kind| kind.to_s.split(",") }.intersection(KINDS)
    @tags = Array(tags).flat_map { |tag| tag.to_s.split(",") }.map { |tag| tag.strip.downcase }.reject(&:blank?).uniq
    @statuses = Array(statuses).flat_map { |status| status.to_s.split(",") }.intersection(Task::STATUSES)
    @priorities = Array(priorities).flat_map { |priority| priority.to_s.split(",") }.intersection(Task::PRIORITIES)
    @limit = [[limit.to_i, 1].max, MAX_LIMIT].min if limit.present?
    @limit ||= DEFAULT_LIMIT
  end

  def call
    request = SearchDocumentsIndex.all
    request = request.query(bool: { must: [keyword_query].compact, filter: filters })
    request = request.highlight(fields: %w[title context intended_direction body].to_h { |field| [field, { fragment_size: 240, number_of_fragments: 1 }] }, pre_tags: ["<em>"], post_tags: ["</em>"]) if @q.present?
    request.limit(@limit).to_a.map { |hit| result_for(hit) }
  end

  private

  def keyword_query
    return if @q.blank?
    { multi_match: { query: @q, fields: ["title^2", "tags^2", "intended_direction^2", "project_name^2", "context^1.5", "body^1.5"], type: "most_fields", fuzziness: "AUTO" } }
  end

  def filters
    filters = [{ term: { user_id: @user.id } }]
    filters << { term: { project_slug: @project } } if @project
    filters << { term: { kind: "note" } } if @scope == "global"
    filters << { bool: { must_not: [{ exists: { field: "project_id" }}] } } if @scope == "global"
    filters << { terms: { kind: @kinds } } if @kinds.present?
    @tags.each { |tag| filters << { term: { tags: tag } } }
    filters << { terms: { status: @statuses } } if @statuses.present?
    filters << { terms: { priority: @priorities } } if @priorities.present?
    filters
  end

  def result_for(hit)
    { id: hit.id.to_i, kind: hit.kind, title: hit.title, project: hit.project_id && { id: hit.project_id.to_i, slug: hit.project_slug, name: hit.project_name }, tags: hit.tags || [], status: hit.status, priority: hit.priority, snippet: snippet_for(hit), highlights: highlights_for(hit), created_at: hit.created_at, updated_at: hit.updated_at }.tap do |result|
      result.delete(:status) if hit.kind != "task"
      result.delete(:priority) if hit.kind != "task"
    end
  end

  def highlights_for(hit)
    %w[title context intended_direction body].each_with_object([]) do |field, highlights|
      values = hit.public_send("#{field}_highlights")
      highlights << { field: field, fragments: values } if values.present?
    end
  end

  def snippet_for(hit)
    highlights_for(hit).first&.dig(:fragments, 0) || hit.title.to_s
  end
end
