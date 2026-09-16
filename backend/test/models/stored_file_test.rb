require "test_helper"
require "stringio"

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

  private

  def create_file(project, filename, bytes)
    file = project.stored_files.create!(filename: filename, media_type: "application/octet-stream", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    file.original.attach(io: StringIO.new(bytes), filename: filename, content_type: file.media_type)
    file
  end
end
