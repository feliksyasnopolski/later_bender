require "zlib"

class FileReader
  MAX_CHARS = 100_000
  TEXT_TYPES = %w[text/plain text/markdown text/x-markdown application/markdown application/json application/xml text/csv].freeze

  def self.generate(file)
    new(file).generate
  end

  def self.read(file, representation: "auto", locator: nil)
    new(file).read(representation:, locator:)
  end

  def self.read_bytes(bytes, filename:, media_type:, representation: "auto", locator: nil)
    new(nil).read_bytes(bytes, filename:, media_type:, representation:, locator:)
  end

  def self.valid_locator?(file, kind, locator)
    new(file).valid_locator?(kind, locator)
  rescue StandardError
    false
  end

  def initialize(file)
    @file = file
  end

  def generate
    bytes = @file.original.download
    if @file.archive?
      ArchiveReader.new(@file).build_manifest
      @file.representations.find_or_initialize_by(kind: "metadata").update!(content: nil, media_type: @file.media_type, generator: "FileReader", generator_version: "1", status: "ready", metadata: { "byte_size" => @file.byte_size, "sha256" => @file.sha256 })
      return
    end
    kind, content, metadata, media_type = derive(bytes)
    @file.representations.find_or_initialize_by(kind: kind).update!(content:, media_type:, generator: "FileReader", generator_version: "1", status: "ready", metadata:)
    @file.representations.find_or_initialize_by(kind: "image_metadata").update!(content: nil, media_type: @file.media_type, generator: "FileReader", generator_version: "1", status: "ready", metadata: image_metadata(bytes)) if @file.media_type.start_with?("image/")
    @file.representations.find_or_initialize_by(kind: "metadata").update!(content: nil, media_type: @file.media_type, generator: "FileReader", generator_version: "1", status: "ready", metadata: { byte_size: @file.byte_size, sha256: @file.sha256 })
  rescue StandardError => e
    @file.representations.find_or_initialize_by(kind: "metadata").update!(media_type: @file.media_type, generator: "FileReader", generator_version: "1", status: "failed", metadata: { error: e.class.name })
  end

  def read(representation: "auto", locator: nil)
    rep = choose(representation)
    raise ActiveRecord::RecordNotFound unless rep
    return { kind: "metadata", representation: rep.kind, coordinate: nil, locator: nil, media_type: rep.media_type, metadata: rep.metadata } if rep.content.blank?

    content = rep.content
    coordinate = rep.metadata["coordinate"] || "lines"
    raise ArgumentError, "Invalid locator" if locator && !valid_locator?(rep.kind, locator)
    effective_locator = locator || full_locator(coordinate, content, rep.metadata)
    content = slice(content, coordinate, locator) if locator
    { kind: coordinate == "pages" ? "pdf" : "text", representation: rep.kind, coordinate:, locator: effective_locator, media_type: rep.media_type, content:, metadata: rep.metadata }
  end

  def read_bytes(bytes, filename:, media_type:, representation: "auto", locator: nil)
    kind, content, metadata, derived_media_type = derive(bytes, filename:, media_type:)
    selected_kind = representation == "auto" ? kind : representation
    raise ActiveRecord::RecordNotFound unless representation == "auto" || selected_kind == kind
    return { kind: "metadata", representation: kind, coordinate: nil, locator: nil, media_type: derived_media_type, metadata: metadata } if content.blank?
    raise ArgumentError, "Invalid locator" if locator && !virtual_valid_locator?(content, metadata["coordinate"], locator, metadata)
    effective_locator = locator || full_locator(metadata["coordinate"], content, metadata)
    content = slice(content, metadata["coordinate"], locator) if locator
    { kind: metadata["coordinate"] == "pages" ? "pdf" : "text", representation: kind, coordinate: metadata["coordinate"], locator: effective_locator, media_type: derived_media_type, content:, metadata: metadata }
  end

  def valid_locator?(kind, locator)
    return false unless locator.is_a?(Hash) && %w[lines pages].include?(locator["kind"] || locator[:kind])
    rep = choose(kind)
    return false unless rep&.content
    key = locator["kind"] || locator[:kind]
    start = (locator["start"] || locator[:start]).to_i
    finish = (locator["end"] || locator[:end]).to_i
    start.positive? && finish >= start && finish <= (key == "pages" ? page_count(rep) : line_count(rep))
  end

  private

  def derive(bytes, filename: @file&.filename, media_type: @file&.media_type)
    if media_type == "application/pdf"
      text, pages = extract_pdf(bytes)
      [ "pdf_text", text, { "coordinate" => "pages", "pages" => pages }, "text/plain" ]
    elsif media_type.start_with?("text/") || TEXT_TYPES.include?(media_type) || filename.match?(/\.(md|markdown|txt|csv|json|xml)\z/i)
      [ media_type.include?("markdown") || filename.match?(/\.(md|markdown)\z/i) ? "markdown" : "text", bytes.force_encoding("UTF-8").scrub.gsub("\r\n", "\n").gsub("\r", "\n"), { "coordinate" => "lines" }, "text/plain" ]
    elsif media_type == "text/html" || filename.match?(/\.html?\z/i)
      [ "html_text", bytes.force_encoding("UTF-8").scrub.gsub(/<script.*?<\/script>|<style.*?<\/style>/mi, "").gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip, { "coordinate" => "lines" }, "text/plain" ]
    else
      [ "metadata", nil, {}, media_type ]
    end
  end

  def virtual_valid_locator?(content, coordinate, locator, metadata)
    key = locator["kind"] || locator[:kind]
    start = (locator["start"] || locator[:start]).to_i
    finish = (locator["end"] || locator[:end]).to_i
    start.positive? && finish >= start && finish <= (key == "pages" ? metadata["pages"].to_i : content.lines.length) && key == coordinate
  end

  def choose(kind)
    return @file.representations.where(status: "ready").find_by(kind: "metadata") if kind == "auto" && @file.media_type.start_with?("image/")
    return @file.representations.where(status: "ready", kind: %w[text markdown html_text pdf_text]).order(:id).first if kind == "auto"
    @file.representations.where(status: "ready").find_by(kind: kind)
  end

  def line_count(rep)
    rep.content.to_s.lines.length
  end

  def page_count(rep)
    rep.metadata["pages"].to_i.nonzero? || rep.content.to_s.scan(/\[P\d+\]/).length
  end

  def slice(content, coordinate, locator)
    start = (locator["start"] || locator[:start]).to_i
    finish = (locator["end"] || locator[:end]).to_i
    if coordinate == "pages"
      pages = content.split(/(?=\[P\d+\])/)
      pages[(start - 1)...finish].to_a.join
    else
      content.lines.each_with_index.map { |line, i| "[L#{i + 1}] #{line}" if i + 1 >= start && i + 1 <= finish }.compact.join
    end
  end

  def full_locator(coordinate, content, metadata)
    finish = coordinate == "pages" ? metadata["pages"].to_i : content.lines.length
    { "kind" => coordinate, "start" => 1, "end" => finish }
  end

  def image_metadata(bytes)
    { "byte_size" => bytes.bytesize, "filename" => @file.filename, "media_type" => @file.media_type }
  end

  def extract_pdf(bytes)
    pages = bytes.scan(/stream\s*\r?\n(.*?)\r?\nendstream/m).map(&:first).map do |stream|
      begin
        Zlib::Inflate.inflate(stream).force_encoding("ISO-8859-1").scan(/\(([^)]*)\)/).flatten.join(" ").encode("UTF-8", invalid: :replace, undef: :replace)
      rescue Zlib::Error
        stream.force_encoding("ISO-8859-1").scan(/\(([^)]*)\)/).flatten.join(" ").encode("UTF-8", invalid: :replace, undef: :replace)
      end
    end
    pages = [ bytes.force_encoding("ISO-8859-1").scan(/\(([^)]*)\)/).flatten.join(" ") ] if pages.empty?
    pages = pages.map.with_index { |page, index| "[P#{index + 1}]\n#{page.strip}\n" }
    [ pages.join("\n"), pages.length ]
  end
end
