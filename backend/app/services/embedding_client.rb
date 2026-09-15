require "net/http"
require "json"

class EmbeddingClient
  DIMENSION = 256

  def initialize(endpoint: ENV.fetch("EMBEDDING_SERVICE_URL", "http://127.0.0.1:18080"), open_timeout: 2, read_timeout: 15)
    @endpoint = endpoint
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def embed(texts, mode:)
    uri = URI.join("#{@endpoint.chomp("/")}/", "embed")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = { mode: mode.to_s, texts: texts }.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @open_timeout, read_timeout: @read_timeout) { |http| http.request(request) }
    raise "embedding service returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    raise "embedding dimension mismatch" unless payload.fetch("dimension").to_i == DIMENSION
    vectors = payload.fetch("embeddings")
    raise "embedding count mismatch" unless vectors.length == texts.length
    raise "embedding vector dimension mismatch" unless vectors.all? { |vector| vector.length == DIMENSION }
    vectors
  rescue JSON::ParserError, KeyError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
    raise "embedding service unavailable: #{e.message}"
  end
end
