require "json"
require "open3"
require "tempfile"

class ArchiveReader
  MAX_ENTRIES = 10_000
  MAX_ENTRY_BYTES = 10 * 1024 * 1024
  MAX_TOTAL_BYTES = 100 * 1024 * 1024
  MAX_LIST_LIMIT = 100
  MANIFEST_KIND = "archive_manifest"
  ARCHIVE_EXTENSIONS = %w[.zip .tar .tgz .gz .bz2 .xz .zst .7z .rar].freeze

  class Error < StandardError; end
  class UnsafePath < Error; end
  class LimitExceeded < Error; end
  class Unsupported < Error; end

  def self.archive_filename?(filename, media_type)
    media_type.to_s.match?(%r{\A(application/(zip|x-7z-compressed|x-rar-compressed)|application/x-(tar|gzip|bzip2|xz|zstd)|application/gzip)\z}) || ARCHIVE_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
  end

  def self.manifest(file)
    representation = file.representations.find_by(kind: MANIFEST_KIND, status: "ready")
    return JSON.parse(representation.content) if representation
    new(file).build_manifest
  end

  def self.list(file, path: nil, depth: nil, limit: nil)
    result = entries(file, path:, depth:)
    requested_limit = limit.nil? ? 50 : Integer(limit)
    result.first([[requested_limit, 1].max, MAX_LIST_LIMIT].min)
  end

  def self.entries(file, path: nil, depth: nil)
    entries = manifest(file)
    prefix = normalize_prefix(path)
    max_depth = depth.nil? ? 1 : Integer(depth)
    raise ArgumentError, "depth must be non-negative" if max_depth.negative?
    entries.select do |entry|
      next false unless prefix.empty? || entry["path"].start_with?(prefix)
      relative = entry["path"].delete_prefix(prefix).delete_prefix("/")
      relative.split("/").length <= max_depth + 1
    end.sort_by { |entry| entry.fetch("path") }
  rescue JSON::ParserError
    raise Error, "archive manifest is invalid"
  end

  def self.read_entry(file, path, representation: "auto", locator: nil)
    entry = find_entry(file, path)
    raise Error, "archive entry is not a readable file" unless entry["kind"] == "file" && entry["readable"]
    bytes = new(file).read_bytes(entry.fetch("path"))
    raise LimitExceeded, "archive entry exceeds read limit" if bytes.bytesize > MAX_ENTRY_BYTES
    FileReader.read_bytes(bytes, filename: entry.fetch("path"), media_type: entry["media_type"] || "application/octet-stream", representation:, locator:)
  end

  def self.find_entry(file, path)
    normalized = normalize_path(path)
    manifest(file).find { |entry| entry["path"] == normalized } || (raise ActiveRecord::RecordNotFound)
  end

  def self.normalize_prefix(path)
    return "" if path.blank?
    "#{normalize_path(path)}/"
  end

  def self.normalize_path(path)
    value = path.to_s
    raise UnsafePath, "invalid archive path" if value.blank? || value.start_with?("/") || value.match?(%r{\A[A-Za-z]:[\\/]})
    parts = value.tr("\\", "/").sub(%r{/\z}, "").split("/")
    raise UnsafePath, "invalid archive path" if parts.any? { |part| part.blank? || part == "." || part == ".." }
    parts.join("/")
  end

  def initialize(file)
    @file = file
  end

  def build_manifest
    rows = []
    with_archive do |path|
      Open3.popen3("bsdtar", "-tvf", path) do |stdin, stdout, stderr, wait|
        stdin.close
        stdout.each_line do |line|
          rows << parse_listing_line(line)
          raise LimitExceeded, "archive has too many members" if rows.length > MAX_ENTRIES
        end
        error = stderr.read
        raise Unsupported, error.presence || "unsupported or malformed archive" unless wait.value.success?
      end
    end
    rows = rows.compact.map { |row| enrich(row) }
    validate_manifest!(rows)
    @file.representations.find_or_initialize_by(kind: MANIFEST_KIND).update!(content: JSON.generate(rows), media_type: "application/json", generator: "ArchiveReader", generator_version: "1", status: "ready", metadata: { "entry_count" => rows.length })
    rows
  rescue StandardError => e
    @file.representations.find_or_initialize_by(kind: MANIFEST_KIND).update(media_type: "application/json", generator: "ArchiveReader", generator_version: "1", status: "failed", metadata: { "error" => e.class.name })
    raise
  end

  def read_bytes(entry_path)
    with_archive do |path|
      output = String.new(encoding: Encoding::BINARY)
      Open3.popen3("bsdtar", "-xOf", path, "--", entry_path) do |stdin, stdout, stderr, wait|
        stdin.close
        until stdout.eof?
          output << stdout.read([64 * 1024, MAX_ENTRY_BYTES + 1 - output.bytesize].min)
          raise LimitExceeded, "archive entry exceeds read limit" if output.bytesize > MAX_ENTRY_BYTES
        end
        error = stderr.read
        raise Error, error.presence || "archive entry could not be read" unless wait.value.success?
      end
      output
    end
  end

  private

  def with_archive
    Tempfile.create(["later-bender-archive", File.extname(@file.filename)]) do |tempfile|
      tempfile.binmode
      tempfile.write(@file.original.download)
      tempfile.flush
      yield tempfile.path
    end
  end

  def parse_listing_line(line)
    match = line.match(/\A(?<mode>.)(?:\S+\s+){4}(?<size>\d+)\s+\S+\s+\S+\s+\S+\s+(?<path>.+?)\s*\z/)
    return unless match
    raw_path = match[:path].sub(/\s+->\s+.*\z/, "")
    mode = match[:mode]
    clean_path = raw_path.sub(%r{\A\./}, "").sub(%r{/\z}, "")
    return if clean_path.blank?
    { "path" => self.class.normalize_path(clean_path), "kind" => mode == "d" ? "directory" : mode == "l" ? "symlink" : "file", "uncompressed_size" => match[:size].to_i, "compressed_size" => nil, "readable" => mode != "l", "encrypted" => false }
  end

  def enrich(row)
    row.merge("media_type" => row["kind"] == "file" ? Marcel::MimeType.for(name: row["path"]) : nil)
  end

  def validate_manifest!(rows)
    raise Error, "duplicate archive paths" unless rows.map { |row| row["path"] }.uniq.length == rows.length
    raise LimitExceeded, "archive is too large" if rows.sum { |row| row["uncompressed_size"].to_i } > MAX_TOTAL_BYTES
    rows.each do |row|
      size = row["uncompressed_size"].to_i
      raise LimitExceeded, "archive entry is too large" if size > MAX_ENTRY_BYTES
      raise LimitExceeded, "archive compression ratio is unreasonable" if size > @file.byte_size * 1000
    end
  end
end
