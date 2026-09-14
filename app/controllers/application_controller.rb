class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: { code: "not_found", message: "Resource not found" } }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |error|
    render_validation_errors(error.record)
  end

  private

  def render_validation_errors(record)
    render json: { error: { code: "validation_failed", message: "Validation failed", details: record.errors.to_hash.transform_values(&:to_a) } }, status: :unprocessable_content
  end
end
