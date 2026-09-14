ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  parallelize(workers: 1)
end

class ActionDispatch::IntegrationTest
  def json_headers(token = nil)
    headers = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    headers
  end

  def json_body
    JSON.parse(response.body)
  end
end
