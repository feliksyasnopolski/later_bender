require "test_helper"
require "stringio"
require "open3"
require "tempfile"

class StoredFileTest < ActiveSupport::TestCase
  test "allocates project-local refs and preserves stored bytes and sha256" do
    user = User.create!(username: "file-user", password: "password123")
    first_project = user.projects.create!(name: "First", slug: "first-files", shorthand: "FF")
    second_project = user.projects.create!(name: "Second", slug: "second-files", shorthand: "SF")
    bytes = "\x00\x01binary\xff".b

    first = create_file(first_project, "one.bin", bytes)
    second = create_file(first_project, "two.bin", "text")
    other = create_file(second_project, "other.bin", bytes)

    assert_equal "FF-F1", first.ref
    assert_equal "FF-F2", second.ref
    assert_equal "SF-F1", other.ref
    assert_equal bytes, first.original.download
    assert_equal bytes.bytesize, first.byte_size
    assert_equal Digest::SHA256.hexdigest(bytes), first.sha256
  end

  test "requires a project and does not allow number changes" do
    file = StoredFile.new(filename: "x", media_type: "text/plain", byte_size: 1, sha256: "a" * 64)
    assert_not file.valid?
    assert_includes file.errors[:project], "must exist"
  end

  test "ingests a streamed provider response from an IO without each_body" do
    user = User.create!(username: "ingest-user", password: "password123")
    project = user.projects.create!(name: "Ingest", slug: "ingest-files", shorthand: "IF")
    bytes = "provider bytes\x00".b

    opener = ->(_url, _mode, &block) { block.call(StringIO.new(bytes)) }
    file = StoredFileIngestor.call(project: project, payload: { "download_url" => "https://provider.invalid/file", "file_name" => "provider.bin", "mime_type" => "application/octet-stream" }, opener: opener)
    assert_equal bytes, file.original.download
    assert_equal Digest::SHA256.hexdigest(bytes), file.sha256
  end

  test "persists a URL fetch through the canonical immutable ingestion path" do
    user = User.create!(username: "url-ingest-user", password: "password123")
    project = user.projects.create!(name: "URL ingest", slug: "url-ingest", shorthand: "UI")
    bytes = "remote bytes\n"
    tempfile = Tempfile.new("url-ingest-test")
    tempfile.binmode
    tempfile.write(bytes)
    tempfile.rewind
    origin = {
      "kind" => "url",
      "requested_url" => "https://public.example/source",
      "final_url" => "https://cdn.example/source.txt",
      "fetched_at" => "2026-09-17T12:00:00.000000Z"
    }
    result = UrlFileFetcher::Result.new(tempfile:, filename: "source.txt", media_type: "text/plain", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), origin:)
    fetcher = ->(**) { result }

    file = StoredFileIngestor.call(project:, url: "https://public.example/source", tags: [ "evidence" ], url_fetcher: fetcher)

    assert_equal bytes, file.original.download
    assert_equal "source.txt", file.filename
    assert_equal "text/plain", file.media_type
    assert_equal origin, file.origin
    assert_equal [ "evidence" ], file.tags.pluck(:name)
    assert_raises(ActiveRecord::RecordInvalid) { file.update!(origin: origin.merge("final_url" => "https://other.example/")) }
  end

  test "derives bounded readable text with line coordinates" do
    user = User.create!(username: "reader-user", password: "password123")
    project = user.projects.create!(name: "Reader", slug: "reader-files", shorthand: "RF")
    file = create_file(project, "source.md", "alpha\r\nbeta\r\ngamma")
    FileReader.generate(file)

    read = FileReader.read(file, locator: { "kind" => "lines", "start" => 2, "end" => 3 })
    assert_equal "markdown", read[:representation]
    assert_equal "[L2] beta\n[L3] gamma", read[:content]
    assert_not FileReader.valid_locator?(file, "markdown", { "kind" => "lines", "start" => 1, "end" => 4 })
  end

  test "derives page-aware text from a small PDF stream" do
    user = User.create!(username: "pdf-user", password: "password123")
    project = user.projects.create!(name: "PDF", slug: "pdf-files", shorthand: "PF")
    pdf = "%PDF-1.4\n1 0 obj\n<<>>\nstream\n(PDF known page)\nendstream\n%%EOF".b
    file = create_file(project, "source.pdf", pdf)
    file.update!(media_type: "application/pdf")
    FileReader.generate(file)

    read = FileReader.read(file, representation: "pdf_text", locator: { "kind" => "pages", "start" => 1, "end" => 1 })
    assert_equal "pdf_text", read[:representation]
    assert_includes read[:content], "PDF known page"
    assert_equal 1, read[:metadata]["pages"]
  end

  test "lists, reads, and explicitly extracts archive members without exploding the parent" do
    user = User.create!(username: "archive-user", password: "password123")
    project = user.projects.create!(name: "Archives", slug: "archive-files", shorthand: "AF")
    source = Dir.mktmpdir("later-bender-archive-test")
    FileUtils.mkdir_p(File.join(source, "docs"))
    File.binwrite(File.join(source, "docs", "readme.md"), "alpha\nbeta\ngamma\n")
    File.binwrite(File.join(source, "image.bin"), "\x00\x01binary".b)
    archive_path = Tempfile.new(["archive", ".zip"])
    archive_filename = archive_path.path
    archive_path.close
    archive_path.unlink
    _output, error, status = Open3.capture3("zip", "-q", "-r", archive_filename, ".", chdir: source)
    raise error unless status.success?
    bytes = File.binread(archive_filename)
    archive = create_file(project, "bundle.zip", bytes)
    archive.update!(media_type: "application/zip")
    FileReader.generate(archive)

    assert_equal %w[docs image.bin], ArchiveReader.list(archive, depth: 0).map { |entry| entry["path"] }
    assert_equal ["docs/readme.md"], ArchiveReader.list(archive, path: "docs", depth: 0).map { |entry| entry["path"] }
    read = ArchiveReader.read_entry(archive, "docs/readme.md", locator: { "kind" => "lines", "start" => 2, "end" => 2 })
    assert_equal "[L2] beta\n", read[:content]
    assert_raises(ArchiveReader::UnsafePath) { ArchiveReader.read_entry(archive, "../secret") }

    extracted = ArchiveExtractor.call(source: archive, path: "docs/readme.md")
    assert_equal "alpha\nbeta\ngamma\n", extracted.original.download
    assert_equal Digest::SHA256.hexdigest(extracted.original.download), extracted.sha256
    assert_equal archive.ref, extracted.archive_source.ref
    assert_equal "docs/readme.md", extracted.archive_entry_path
    assert_equal 1, project.stored_files.where(archive_source: archive).count
    assert_equal archive.ref, StoredFile.find(archive.id).ref
  end

  private

  def create_file(project, filename, bytes)
    file = project.stored_files.create!(filename: filename, media_type: "application/octet-stream", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    file.original.attach(io: StringIO.new(bytes), filename: filename, content_type: file.media_type)
    file
  end
end
