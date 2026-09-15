class OauthRegistrationController < ActionController::API
  def create
    metadata = params.to_unsafe_h.slice("client_name", "redirect_uris", "scope", "grant_types", "response_types", "token_endpoint_auth_method")
    redirect_uris = metadata["redirect_uris"].presence || metadata["redirect_uri"].presence
    redirect_uris = redirect_uris.is_a?(Array) ? redirect_uris : redirect_uris.to_s
    application = Doorkeeper::Application.create!({
      name: metadata["client_name"].presence || "MCP client",
      redirect_uri: redirect_uris,
      scopes: "mcp",
      confidential: false
    })
    render json: {
      client_id: application.uid,
      client_name: application.name,
      redirect_uris: application.redirect_uri.split,
      grant_types: [ "authorization_code", "refresh_token" ],
      response_types: [ "code" ],
      token_endpoint_auth_method: "none",
      scope: "mcp"
    }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: "invalid_client_metadata", error_description: error.record.errors.full_messages.to_sentence }, status: :bad_request
  end
end
