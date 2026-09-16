class SearchDocumentsIndex < Chewy::Index
  index_scope -> { SearchDocuments.all }, name: "search_documents"

  root id: ->(record) { "#{record.class.name.underscore}-#{record.id}" } do
  field :id, type: "keyword", value: ->(record) { record.id }
  field :ref, type: "keyword", value: ->(record) { record.ref if record.is_a?(Task) || record.is_a?(StoredFile) }
  field :number, type: "integer", value: ->(record) { record.number if record.is_a?(Task) || record.is_a?(StoredFile) }
  field :kind, type: "keyword", value: ->(record) { record.is_a?(StoredFile) ? "file" : record.class.name.underscore }
  field :user_id, type: "integer", value: ->(record) { record.project.user_id }
  field :project_id, type: "integer", value: ->(record) { record.project_id }
  field :project_slug, type: "keyword", value: ->(record) { record.project&.slug }
  field :project_name, type: "text", value: ->(record) { record.project&.name }
  field :project_shorthand, type: "keyword", value: ->(record) { record.project&.shorthand }
  field :title, type: "text", value: ->(record) { record.is_a?(StoredFile) ? record.filename : record.title }
  field :tags, type: "keyword", value: ->(record) { record.tags.map(&:name) }
  field :created_at, type: "date", value: ->(record) { record.created_at }
  field :updated_at, type: "date", value: ->(record) { record.updated_at }
  field :context, type: "text", value: ->(record) { record.context if record.is_a?(Task) }
  field :intended_direction, type: "text", value: ->(record) { record.intended_direction if record.is_a?(Task) }
  field :status, type: "keyword", value: ->(record) { record.status if record.is_a?(Task) }
  field :priority, type: "keyword", value: ->(record) { record.priority if record.is_a?(Task) }
  field :filename, type: "keyword", value: ->(record) { record.filename if record.is_a?(StoredFile) }
  field :media_type, type: "keyword", value: ->(record) { record.media_type if record.is_a?(StoredFile) }
  field :representation, type: "keyword", value: ->(record) { record.searchable_representation&.kind if record.is_a?(StoredFile) }
  field :locator, type: "object", enabled: false, value: ->(record) { { "kind" => record.searchable_representation&.metadata&.fetch("coordinate", "lines"), "start" => 1, "end" => record.searchable_text.lines.length } if record.is_a?(StoredFile) }
  field :related_note_ids, type: "integer", value: ->(record) { record.notes.map(&:id) if record.is_a?(Task) }
    field :body, type: "text", value: ->(record) { record.is_a?(Note) ? record.body : record.searchable_text if record.is_a?(StoredFile) }
  end
end
