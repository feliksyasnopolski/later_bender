class ApplicationController < ActionController::API
  before_action :authenticate_api_token!

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: { code: "not_found", message: "Resource not found" } }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |error|
    render_validation_errors(error.record)
  end

  private

  attr_reader :current_api_token

  def authenticate_api_token!
    raw_token = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
    @current_api_token = ApiToken.authenticate(raw_token)
    return if @current_api_token
    render json: { error: { code: "unauthorized", message: "A valid bearer token is required" } }, status: :unauthorized
  end

  def render_validation_errors(record)
    render json: { error: { code: "validation_failed", message: "Validation failed", details: record.errors.to_hash.transform_values(&:to_a) } }, status: :unprocessable_content
  end
end
