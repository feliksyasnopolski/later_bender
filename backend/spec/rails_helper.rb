ENV["RAILS_ENV"] ||= "test"
require File.expand_path("../../config/environment", __FILE__)
require "rspec/rails"
require "factory_bot_rails"
require_relative "support/search_hit"

abort("The Rails environment is running in production mode!") if Rails.env.production?

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include ActiveSupport::Testing::Assertions
  config.include ActionDispatch::Assertions

  config.before(:suite) do
    Rails.application.load_tasks
  end
end

module AssertionCompatibility
  def assert(value, message = nil)
    expect(value).to be_truthy, message
  end

  def assert_equal(expected, actual, message = nil)
    expect(actual).to eq(expected), message
  end

  def assert_includes(collection, object, message = nil)
    expect(collection).to include(object), message
  end

  def assert_not_includes(collection, object, message = nil)
    expect(collection).not_to include(object), message
  end

  def assert_not(value, message = nil)
    expect(value).to be_falsey, message
  end

  def assert_nil(value, message = nil)
    expect(value).to be_nil, message
  end

  def assert_operator(actual, operator, expected, message = nil)
    expect(actual).to satisfy(message) { |value| value.public_send(operator, expected) }
  end

  def assert_match(pattern, value, message = nil)
    expect(value).to match(pattern), message
  end

  def assert_response(status, message = nil)
    expect(response).to have_http_status(status), message
  end

  def assert_raises(*exceptions, &block)
    expect(&block).to raise_error(*exceptions)
  end
end

RSpec.configure do |config|
  config.include AssertionCompatibility
  config.include FactoryBot::Syntax::Methods
end

def json_headers(token = nil)
  headers = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
  headers["Authorization"] = "Bearer #{token}" if token
  headers
end

def json_body
  JSON.parse(response.body)
end
