require "digest"
require "open-uri"
require "tempfile"

class StoredFileIngestor
  MAX_BYTES = Integer(ENV.fetch("MAX_FILE_UPLOAD_BYTES", 100 * 1024 * 1024))

  def self.call(...)
    new(...).call
  end

  def initialize(project:, payload:, filename: nil, tags: nil, related_task_refs: nil, related_note_ids: nil, opener: URI.method(:open))
    @project = project
    @payload = payload
    @filename = filename.presence || payload["file_name"].presence
    @tags = tags
    @related_task_refs = related_task_refs
    @related_note_ids = related_note_ids
    @opener = opener
  end

  def call
    raise ActiveRecord::RecordInvalid, invalid_record("filename", "is required") if @filename.blank?
    tasks = resolve_tasks if @related_task_refs
    notes = resolve_notes if @related_note_ids

    tempfile = Tempfile.new([ "later-bender-file", File.extname(@filename) ])
    tempfile.binmode
    digest = Digest::SHA256.new
    begin
      byte_size = download_to(tempfile, digest)
    rescue OpenURI::HTTPError, SocketError, Timeout::Error, IOError => error
      raise ActiveRecord::RecordInvalid, invalid_record("file", "provider download failed: #{error.message}")
    end
    tempfile.rewind
    media_type = supplied_media_type.presence || "application/octet-stream"

    begin
      StoredFile.transaction do
        file = @project.stored_files.new(filename: @filename, media_type: media_type, byte_size: byte_size, sha256: digest.hexdigest)
        file.save!
        file.original.attach(io: tempfile, filename: @filename, content_type: media_type)
        file.update!(byte_size: byte_size, sha256: digest.hexdigest)
        TagReconciler.call(file, @tags) if @tags
        file.tasks = tasks if @related_task_refs
        file.notes = notes if @related_note_ids
        file
      end
    ensure
      begin
        tempfile.close!
      rescue IOError
        nil
      end
    end
  end

  private

  def download_to(tempfile, digest)
    raise ActiveRecord::RecordInvalid, invalid_record("file", "download_url is required") unless @payload["download_url"].present?
    size = 0
    @opener.call(@payload.fetch("download_url"), "rb") do |stream|
      @download_media_type = stream.content_type if stream.respond_to?(:content_type)
      while (chunk = stream.read(64 * 1024))
        size += chunk.bytesize
        raise ActiveRecord::RecordInvalid, invalid_record("file", "exceeds upload size limit") if size > MAX_BYTES
        tempfile.write(chunk)
        digest.update(chunk)
      end
    end
    size
  end

  def supplied_media_type
    @payload["mime_type"].presence || @payload["content_type"].presence || @download_media_type
  end

  def resolve_tasks
    refs = Array(@related_task_refs).map(&:to_s).uniq
    tasks = refs.map do |ref|
      shorthand, number = ref.split("-", 2)
      @project.tasks.find_by!(number: number) if shorthand.to_s.casecmp?(@project.shorthand) && number.present?
    end
    raise ActiveRecord::RecordNotFound if tasks.any?(&:nil?)
    tasks
  end

  def resolve_notes
    ids = Array(@related_note_ids).map(&:to_i).uniq
    notes = @project.user.notes.where(id: ids).to_a
    raise ActiveRecord::RecordNotFound if notes.size != ids.size
    notes
  end

  def invalid_record(field, message)
    record = StoredFile.new
    record.errors.add(field, message)
    record
  end
end
