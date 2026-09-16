class SemanticChunksIndex < Chewy::Index
  index_name "semantic_chunks"

  root id: ->(record) { record.fetch(:id) } do
    field :kind, type: "keyword"
    field :parent_id, type: "integer"
    field :ref, type: "keyword"
    field :number, type: "integer"
    field :chunk_index, type: "integer"
    field :chunk_text, type: "text"
    field :vector, type: "dense_vector", dims: 256, index: true, similarity: "cosine"
    field :user_id, type: "integer"
    field :project_id, type: "integer"
    field :project_slug, type: "keyword"
    field :project_name, type: "text"
    field :project_shorthand, type: "keyword"
    field :tags, type: "keyword"
    field :status, type: "keyword"
    field :priority, type: "keyword"
    field :title, type: "text"
    field :created_at, type: "date"
    field :updated_at, type: "date"
    field :representation, type: "keyword"
    field :locator, type: "object", enabled: false
    field :filename, type: "keyword"
    field :media_type, type: "keyword"
  end
end
