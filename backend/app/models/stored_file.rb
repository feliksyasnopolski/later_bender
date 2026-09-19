class StoredFile < ApplicationRecord
  belongs_to :project
  belongs_to :archive_source, class_name: "StoredFile", optional: true
  has_many :extracted_files, class_name: "StoredFile", foreign_key: :archive_source_id, dependent: :restrict_with_exception
  has_one_attached :original
  has_many :file_tags, dependent: :destroy
  has_many :tags, through: :file_tags
  has_many :file_tasks, dependent: :destroy
  has_many :tasks, through: :file_tasks
  has_many :file_notes, dependent: :destroy
  has_many :notes, through: :file_notes
  has_many :representations, class_name: "FileRepresentation", dependent: :destroy
  has_many :citations, dependent: :restrict_with_exception

  validates :number, presence: true, numericality: { only_integer: true }, uniqueness: { scope: :project_id }
  validates :filename, presence: true
  validates :byte_size, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sha256, presence: true, format: { with: /\A\h{64}\z/ }
  validate :number_is_immutable, on: :update
  validate :origin_is_immutable, on: :update
  validate :url_origin_is_valid
  validate :original_is_attached
  validate :archive_provenance_is_complete
  before_validation :allocate_number, on: :create
  after_commit :prepare_and_index, on: %i[create update]

  def ref
    "#{project.shorthand}-F#{number}"
  end

  def searchable_representation
    representations.where(kind: %w[text markdown html_text pdf_text], status: "ready").order(:id).first
  end

  def searchable_text
    searchable_representation&.content.to_s
  end

  def archive?
    ArchiveReader.archive_filename?(filename, media_type)
  end

  private

  def prepare_and_index
    generate_representations if representations.none?
    index_search_content
  end

  def generate_representations
    FileReader.generate(self)
  rescue StandardError => e
    Rails.logger.warn("file representation deferred for #{ref}: #{e.class}: #{e.message}")
  end

  def index_search_content
    SearchDocumentsIndex.import([ self ])
    SemanticIndexer.call(self)
  rescue StandardError => e
    Rails.logger.warn("file indexing deferred for #{ref}: #{e.class}: #{e.message}")
  end

  def allocate_number
    return unless project&.persisted?
    project.with_lock do
      self.number ||= project.next_file_number
      project.update_columns(next_file_number: [ project.next_file_number, number + 1 ].max, updated_at: Time.current)
    end
  end

  def number_is_immutable
    errors.add(:number, "cannot be changed") if number_changed?
  end

  def origin_is_immutable
    errors.add(:origin, "cannot be changed") if origin_changed?
  end

  def url_origin_is_valid
    return if origin.blank?
    required = %w[kind requested_url final_url fetched_at]
    errors.add(:origin, "is invalid") unless origin.is_a?(Hash) && origin["kind"] == "url" && required.all? { |key| origin[key].present? }
  end

  def original_is_attached
    errors.add(:original, "must be attached") unless original.attached? || new_record?
  end

  def archive_provenance_is_complete
    return if archive_source_id.blank? == archive_entry_path.blank?
    errors.add(:base, "archive provenance must include source and entry path")
  end
end
