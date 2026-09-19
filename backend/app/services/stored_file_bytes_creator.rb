require "digest"
require "tempfile"

class StoredFileBytesCreator
  def self.call(...)
    new(...).call
  end

  def initialize(project:, bytes:, filename:, media_type: "application/octet-stream", tags: nil)
    @project = project
    @bytes = bytes.b
    @filename = filename.to_s.presence || "artifact"
    @media_type = media_type.to_s.presence || "application/octet-stream"
    @tags = tags
  end

  def call
    tempfile = Tempfile.new([ "later-bender-file", File.extname(@filename) ])
    tempfile.binmode
    tempfile.write(@bytes)
    tempfile.rewind
    StoredFile.transaction do
      file = @project.stored_files.new(filename: @filename, media_type: @media_type, byte_size: @bytes.bytesize, sha256: Digest::SHA256.hexdigest(@bytes))
      file.save!
      file.original.attach(io: tempfile, filename: @filename, content_type: @media_type)
      TagReconciler.call(file, @tags) if @tags
      file
    end
  ensure
    tempfile&.close!
  end
end
