SearchHit = Struct.new(:record, :kind, :representation, :locator, :title_highlights, :context_highlights, :intended_direction_highlights, :body_highlights, keyword_init: true) do
  delegate :id, :project, :project_id, :created_at, :updated_at, to: :record

  def ref = record.respond_to?(:ref) ? record.ref : nil
  def number = record.respond_to?(:number) ? record.number : nil
  def filename = record.respond_to?(:filename) ? record.filename : nil
  def media_type = record.respond_to?(:media_type) ? record.media_type : nil

  def project_slug = project&.slug
  def project_name = project&.name
  def project_shorthand = project&.shorthand
  def title = record.is_a?(StoredFile) ? record.filename : record.title
  def tags = record.tags.order(:name).pluck(:name)
  def status = record.respond_to?(:status) ? record.status : nil
  def priority = record.respond_to?(:priority) ? record.priority : nil

  def initialize(**attributes)
    super(title_highlights: [], context_highlights: [], intended_direction_highlights: [], body_highlights: [], **attributes)
  end
end
