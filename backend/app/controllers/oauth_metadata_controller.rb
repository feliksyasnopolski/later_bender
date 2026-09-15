class OauthMetadataController < ActionController::API
  def show
    render json: {
      issuer: oauth_issuer,
      authorization_endpoint: "#{oauth_issuer}/oauth/authorize",
      token_endpoint: "#{oauth_issuer}/oauth/token",
      registration_endpoint: "#{oauth_issuer}/oauth/register",
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      code_challenge_methods_supported: [ "S256" ],
      token_endpoint_auth_methods_supported: [ "none" ],
      scopes_supported: [ "mcp" ]
    }
  end

  private

  def oauth_issuer
    ENV.fetch("LATER_BENDER_OAUTH_ISSUER", "https://laterbender-api.felixworks.v6.rocks")
  end
end
