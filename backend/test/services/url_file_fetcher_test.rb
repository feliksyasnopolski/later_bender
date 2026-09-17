require "test_helper"

class UrlFileFetcherTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :headers, :chunks) do
    def [](name)
      headers[name.downcase]
    end

    def read_body
      chunks.each { |chunk| yield chunk }
    end
  end

  test "downloads exact HTTPS bytes with explicit filename and transport provenance" do
    response = fake_response(200, [ "exact ", "bytes\x00".b ], "content-type" => "text/plain; charset=utf-8", "content-disposition" => 'attachment; filename="ignored.txt"', "etag" => '"v1"', "last-modified" => "Wed, 17 Sep 2026 10:00:00 GMT")
    result, requests = fetch("https://public.example/source", response, filename: "chosen.txt", clock: -> { Time.utc(2026, 9, 17, 12, 0, 0) })

    assert_equal "exact bytes\x00".b, result.tempfile.read
    assert_equal "chosen.txt", result.filename
    assert_equal "text/plain", result.media_type
    assert_equal 12, result.byte_size
    assert_equal Digest::SHA256.hexdigest("exact bytes\x00".b), result.sha256
    assert_equal "8.8.8.8", requests.fetch(0).fetch(:address)
    assert_equal({
      "kind" => "url",
      "requested_url" => "https://public.example/source",
      "final_url" => "https://public.example/source",
      "fetched_at" => "2026-09-17T12:00:00.000000Z",
      "etag" => '"v1"',
      "last_modified" => "Wed, 17 Sep 2026 10:00:00 GMT"
    }, result.origin)
  ensure
    result&.tempfile&.close!
  end

  test "supports HTTP and filename precedence fallbacks" do
    disposition, = fetch("http://public.example/path/original", fake_response(200, [ "one" ], "content-disposition" => "attachment; filename*=UTF-8''report%20one.txt"))
    assert_equal "report one.txt", disposition.filename
    disposition.tempfile.close!

    basename, = fetch("https://public.example/path/report.pdf?version=1", fake_response(200, [ "%PDF-1.4\n" ]), resolver: public_resolver)
    assert_equal "report.pdf", basename.filename
    assert_equal "application/pdf", basename.media_type
    basename.tempfile.close!

    fallback, = fetch("https://public.example/", fake_response(200, [ "data" ]))
    assert_equal "download", fallback.filename
    fallback.tempfile.close!
  end

  test "follows bounded redirects and records requested and final URLs" do
    responses = {
      "https://public.example/start" => fake_response(302, [], "location" => "https://cdn.example/final.txt"),
      "https://cdn.example/final.txt" => fake_response(200, [ "final" ])
    }
    result, requests = fetch("https://public.example/start", responses)

    assert_equal [ "public.example", "cdn.example" ], requests.map { |request| request.fetch(:host) }
    assert_equal "https://public.example/start", result.origin.fetch("requested_url")
    assert_equal "https://cdn.example/final.txt", result.origin.fetch("final_url")
  ensure
    result&.tempfile&.close!
  end

  test "rejects advertised and streamed over-limit bodies" do
    error = assert_fetch_error("file_too_large") do
      fetch("https://public.example/big", fake_response(200, [], "content-length" => "5"), max_bytes: 4)
    end
    assert_equal "URL file exceeds the size limit", error.message

    assert_fetch_error("file_too_large") do
      fetch("https://public.example/stream", fake_response(200, [ "123", "45" ]), max_bytes: 4)
    end
  end

  test "returns stable errors for timeout HTTP failure empty response and redirect limit" do
    assert_fetch_error("fetch_timeout") { fetch("https://public.example/slow", Net::ReadTimeout.new("secret socket detail")) }
    assert_fetch_error("upstream_http_failure") { fetch("https://public.example/missing", fake_response(404, [ "not found" ])) }
    assert_fetch_error("empty_fetch") { fetch("https://public.example/empty", fake_response(200, [])) }
    assert_fetch_error("too_many_redirects") do
      fetch("https://public.example/a", {
        "https://public.example/a" => fake_response(302, [], "location" => "/b"),
        "https://public.example/b" => fake_response(302, [], "location" => "/c")
      }, max_redirects: 1)
    end
  end

  test "rejects malformed unsupported authenticated and private destinations" do
    assert_fetch_error("invalid_url") { fetch("https://", fake_response(200, [ "x" ])) }
    assert_fetch_error("unsupported_url_scheme") { fetch("ftp://public.example/file", fake_response(200, [ "x" ])) }
    assert_fetch_error("invalid_url") { fetch("https://user:pass@public.example/file", fake_response(200, [ "x" ])) }

    %w[127.0.0.1 10.1.2.3 169.254.169.254 192.168.1.1 ::1 ::2 fe80::1 fd00::1].each do |address|
      assert_fetch_error("blocked_destination") do
        fetch("https://internal.example/file", fake_response(200, [ "x" ]), resolver: ->(*) { [ address ] })
      end
    end
  end


  test "allows a globally routable IPv6 destination" do
    result, requests = fetch("https://ipv6.example/file.txt", fake_response(200, [ "ipv6" ]), resolver: ->(*) { [ "2606:4700:4700::1111" ] })
    assert_equal "2606:4700:4700::1111", requests.fetch(0).fetch(:address)
    assert_equal "ipv6", result.tempfile.read
  ensure
    result&.tempfile&.close!
  end

  test "rejects a hostname or redirect that resolves into blocked address space" do
    assert_fetch_error("blocked_destination") do
      fetch("https://mixed.example/file", fake_response(200, [ "x" ]), resolver: ->(*) { [ "8.8.8.8", "10.0.0.1" ] })
    end

    resolver = ->(host, *) { host == "public.example" ? [ "8.8.8.8" ] : [ "127.0.0.1" ] }
    assert_fetch_error("redirect_blocked_destination") do
      fetch("https://public.example/start", fake_response(302, [], "location" => "http://localhost/private"), resolver:)
    end
  end

  private

  def fake_response(code, chunks, headers = {})
    FakeResponse.new(code.to_s, headers.transform_keys(&:downcase), chunks)
  end

  def public_resolver
    ->(*) { [ "8.8.8.8" ] }
  end

  def fetch(url, responses, resolver: public_resolver, **options)
    requests = []
    factory = lambda do |uri, address|
      requests << { host: uri.hostname, address: }
      response = responses.is_a?(Hash) ? responses.fetch(uri.to_s) : responses
      Object.new.tap do |http|
        http.define_singleton_method(:request) do |_request, &block|
          raise response if response.is_a?(Exception)
          block.call(response)
        end
      end
    end
    [ UrlFileFetcher.call(url:, resolver:, http_factory: factory, **options), requests ]
  end

  def assert_fetch_error(code)
    error = assert_raises(FileIngestionError) { yield }
    assert_equal code, error.code
    error
  end
end
