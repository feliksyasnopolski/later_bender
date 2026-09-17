require "digest"
require "ipaddr"
require "marcel"
require "net/http"
require "resolv"
require "tempfile"
require "timeout"
require "uri"

class UrlFileFetcher
  Result = Data.define(:tempfile, :filename, :media_type, :byte_size, :sha256, :origin)

  MAX_BYTES = Integer(ENV.fetch("MAX_FILE_UPLOAD_BYTES", 100 * 1024 * 1024))
  MAX_REDIRECTS = Integer(ENV.fetch("URL_FILE_MAX_REDIRECTS", 5))
  OPEN_TIMEOUT = Float(ENV.fetch("URL_FILE_OPEN_TIMEOUT", 5))
  READ_TIMEOUT = Float(ENV.fetch("URL_FILE_READ_TIMEOUT", 10))
  TOTAL_TIMEOUT = Float(ENV.fetch("URL_FILE_TOTAL_TIMEOUT", 30))
  GLOBAL_IPV6 = IPAddr.new("2000::/3")

  BLOCKED_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
    198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fc00::/7 fe80::/10 2001:db8::/32 ff00::/8
  ].map { |network| IPAddr.new(network) }.freeze

  def self.call(...)
    new(...).call
  end

  def initialize(url:, filename: nil, resolver: nil, http_factory: nil, clock: -> { Time.current }, max_bytes: MAX_BYTES, max_redirects: MAX_REDIRECTS)
    @requested_url = url
    @explicit_filename = filename.presence
    @resolver = resolver || method(:resolve_addresses)
    @http_factory = http_factory || method(:build_http)
    @clock = clock
    @max_bytes = max_bytes
    @max_redirects = max_redirects
  end

  def call
    tempfile = Tempfile.new("later-bender-url")
    tempfile.binmode
    result = Timeout.timeout(TOTAL_TIMEOUT) { fetch_to(tempfile, @requested_url, 0) }
    tempfile.rewind
    Result.new(tempfile:, **result)
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
    tempfile&.close!
    raise FileIngestionError.new("fetch_timeout", "URL fetch timed out")
  rescue FileIngestionError
    tempfile&.close!
    raise
  rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
    tempfile&.close!
    raise FileIngestionError.new("upstream_http_failure", "URL fetch failed")
  end

  private

  def fetch_to(tempfile, raw_url, redirect_count)
    uri = parse_url(raw_url)
    address = public_address(uri.hostname, uri.port, redirected: redirect_count.positive?)
    response_result = nil

    @http_factory.call(uri, address).request(Net::HTTP::Get.new(uri.request_uri, { "Accept" => "*/*", "User-Agent" => "Later-Bender/1 URL fetch" })) do |response|
      status = response.code.to_i
      if status.between?(300, 399)
        raise FileIngestionError.new("too_many_redirects", "URL fetch exceeded the redirect limit") if redirect_count >= @max_redirects
        location = response["location"].to_s
        raise FileIngestionError.new("upstream_http_failure", "URL redirect did not include a valid location") if location.blank?
        begin
          redirected_url = URI.join(uri.to_s, location).to_s
        rescue URI::InvalidURIError
          raise FileIngestionError.new("upstream_http_failure", "URL redirect did not include a valid location")
        end
        return fetch_to(tempfile, redirected_url, redirect_count + 1)
      end
      unless status.between?(200, 299)
        raise FileIngestionError.new("upstream_http_failure", "URL fetch returned HTTP #{status}")
      end

      advertised_size = parse_content_length(response["content-length"])
      raise FileIngestionError.new("file_too_large", "URL file exceeds the size limit") if advertised_size && advertised_size > @max_bytes

      digest = Digest::SHA256.new
      byte_size = 0
      response.read_body do |chunk|
        byte_size += chunk.bytesize
        raise FileIngestionError.new("file_too_large", "URL file exceeds the size limit") if byte_size > @max_bytes
        tempfile.write(chunk)
        digest.update(chunk)
      end
      raise FileIngestionError.new("empty_fetch", "URL fetch returned an empty file") if byte_size.zero?

      filename = effective_filename(response["content-disposition"], uri)
      tempfile.rewind
      declared_type = response["content-type"].to_s.split(";", 2).first.presence
      media_type = Marcel::MimeType.for(tempfile, name: filename, declared_type:) || "application/octet-stream"
      response_result = {
        filename:,
        media_type:,
        byte_size:,
        sha256: digest.hexdigest,
        origin: {
          "kind" => "url",
          "requested_url" => normalized_url(@requested_url),
          "final_url" => normalized_url(uri.to_s),
          "fetched_at" => @clock.call.iso8601(6),
          "etag" => response["etag"].presence,
          "last_modified" => response["last-modified"].presence
        }.compact
      }
    end
    response_result || raise(FileIngestionError.new("upstream_http_failure", "URL fetch failed"))
  end

  def parse_url(value)
    uri = URI.parse(value.to_s)
    raise FileIngestionError.new("unsupported_url_scheme", "URL scheme must be http or https") unless uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme&.downcase)
    raise FileIngestionError.new("invalid_url", "URL is invalid") if uri.hostname.blank? || uri.userinfo.present?
    uri.fragment = nil
    uri
  rescue URI::InvalidURIError, ArgumentError
    raise FileIngestionError.new("invalid_url", "URL is invalid")
  end

  def public_address(hostname, port, redirected:)
    addresses = Array(@resolver.call(hostname, port)).uniq
    raise FileIngestionError.new("upstream_http_failure", "URL destination could not be resolved") if addresses.empty?
    if addresses.any? { |address| blocked_address?(address) }
      code = redirected ? "redirect_blocked_destination" : "blocked_destination"
      message = redirected ? "URL redirect points to a blocked destination" : "URL points to a blocked destination"
      raise FileIngestionError.new(code, message)
    end
    addresses.first
  rescue Resolv::ResolvError, SocketError, IPAddr::InvalidAddressError
    raise FileIngestionError.new("upstream_http_failure", "URL destination could not be resolved")
  end

  def blocked_address?(value)
    address = IPAddr.new(value)
    address = address.native if address.ipv4_mapped?
    return true if address.ipv6? && !GLOBAL_IPV6.include?(address)
    BLOCKED_NETWORKS.any? { |network| network.include?(address) }
  end

  def resolve_addresses(hostname, port)
    Addrinfo.getaddrinfo(hostname, port, nil, :STREAM).map(&:ip_address)
  end

  def build_http(uri, address)
    Net::HTTP.new(uri.hostname, uri.port, nil).tap do |http|
      http.ipaddr = address
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.write_timeout = READ_TIMEOUT
    end
  end

  def effective_filename(content_disposition, uri)
    candidate = @explicit_filename || disposition_filename(content_disposition) || url_basename(uri) || "download"
    basename = File.basename(candidate.to_s.tr("\\", "/"))
    sanitized = ActiveStorage::Filename.new(basename).sanitized
    sanitized.presence || "download"
  end

  def disposition_filename(value)
    return if value.blank?
    if (match = value.match(/filename\*\s*=\s*UTF-8'[^']*'([^;]+)/i))
      return URI::DEFAULT_PARSER.unescape(match[1].strip.delete_prefix('"').delete_suffix('"'))
    end
    match = value.match(/filename\s*=\s*(?:"((?:\\.|[^"])*)"|([^;]+))/i)
    (match&.[](1) || match&.[](2))&.gsub(/\\(.)/, "\\1")&.strip
  rescue ArgumentError
    nil
  end

  def url_basename(uri)
    basename = File.basename(URI::DEFAULT_PARSER.unescape(uri.path.to_s))
    basename unless basename.blank? || basename == "/" || basename == "."
  rescue ArgumentError
    nil
  end

  def parse_content_length(value)
    return if value.blank?
    length = Integer(value, 10)
    raise ArgumentError if length.negative?
    length
  rescue ArgumentError
    raise FileIngestionError.new("upstream_http_failure", "URL fetch returned an invalid Content-Length")
  end

  def normalized_url(value)
    uri = parse_url(value)
    uri.to_s
  end
end
