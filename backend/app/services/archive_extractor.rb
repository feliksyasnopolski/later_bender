require "digest"
require "stringio"
require "tempfile"

class ArchiveExtractor
  def self.call(source:, path:, project: nil, filename: nil, tags: nil, related_task_refs: nil, related_note_ids: nil)
    new(source:, path:, project:, filename:, tags:, related_task_refs:, related_note_ids:).call
  end

  def initialize(source:, path:, project:, filename:, tags:, related_task_refs:, related_note_ids:)
    @source, @path, @project = source, path, project || source.project
    @filename, @tags = filename.presence || File.basename(path.to_s), tags
    @related_task_refs, @related_note_ids = related_task_refs, related_note_ids
  end

  def call
    entry = ArchiveReader.find_entry(@source, @path)
    raise ArchiveReader::Error, "archive entry is not a readable file" unless entry["kind"] == "file" && entry["readable"]
    bytes = ArchiveReader.new(@source).read_bytes(entry.fetch("path"))
    raise ArchiveReader::LimitExceeded, "archive entry exceeds read limit" if bytes.bytesize > ArchiveReader::MAX_ENTRY_BYTES
    tasks = resolve_tasks
    notes = resolve_notes
    file = nil
    StoredFile.transaction do
      file = @project.stored_files.new(filename: @filename, media_type: entry["media_type"] || "application/octet-stream", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), archive_source: @source, archive_entry_path: entry.fetch("path"))
      file.save!
      file.original.attach(io: StringIO.new(bytes), filename: @filename, content_type: file.media_type)
      TagReconciler.call(file, @tags) if @tags
      file.tasks = tasks if @related_task_refs
      file.notes = notes if @related_note_ids
    end
    file
  end

  private

  def resolve_tasks
    return [] unless @related_task_refs
    Array(@related_task_refs).map do |ref|
      shorthand, number = ref.to_s.split("-", 2)
      raise ActiveRecord::RecordNotFound unless shorthand.to_s.casecmp?(@project.shorthand) && number.present?
      @project.tasks.find_by!(number: number)
    end.uniq
  end

  def resolve_notes
    return [] unless @related_note_ids
    ids = Array(@related_note_ids).map(&:to_i).uniq
    notes = @project.user.notes.where(id: ids).to_a
    raise ActiveRecord::RecordNotFound if notes.size != ids.size
    notes
  end
end
