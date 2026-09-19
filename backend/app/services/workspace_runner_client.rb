require "net/http"
require "json"

class WorkspaceRunnerClient
  class Unavailable < StandardError
    attr_reader :code

    def initialize(message, code: nil)
      @code = code
      super(message)
    end
  end

  def initialize(base_url: ENV["WORKSPACE_RUNNER_URL"])
    @base_url = base_url.to_s.sub(%r{/\z}, "")
    @token = ENV["WORKSPACE_RUNNER_TOKEN"]
  end

  def request(method, path, payload = nil)
    raise Unavailable, "Workspace runner is not configured" if @base_url.blank?
    uri = URI("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    request = Net::HTTP.const_get(method.capitalize).new(uri)
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{@token}" if @token.present?
    if payload
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
    end
    response = http.request(request)
    body = JSON.parse(response.body.presence || "{}")
    unless response.is_a?(Net::HTTPSuccess)
      error = body["error"] || {}
      raise Unavailable.new(error["message"] || "Workspace runner request failed", code: error["code"])
    end
    body
  rescue SocketError, SystemCallError, Timeout::Error => e
    raise Unavailable.new(e.message)
  end
end
