class OauthMetadataController < ActionController::API
  ISSUER_HOSTS = %w[lb-api.felix.pp.ua lb-api.felixworks.top].freeze

  def show
    origin = oauth_origin
    return head :bad_request unless origin

    render json: {
      issuer: origin,
      authorization_endpoint: "#{origin}/oauth/authorize",
      token_endpoint: "#{origin}/oauth/token",
      registration_endpoint: "#{origin}/oauth/register",
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      code_challenge_methods_supported: [ "S256" ],
      token_endpoint_auth_methods_supported: [ "none" ],
      scopes_supported: [ "mcp" ]
    }
  end

  private

  # The ingress preserves the public Host header. Ignore X-Forwarded-Host as an
  # origin source; when present, require it to agree with Host so proxy/header
  # ambiguity cannot select another issuer identity.
  def oauth_origin
    host = canonical_public_host(request.get_header("HTTP_HOST"))
    forwarded_host = request.get_header("HTTP_X_FORWARDED_HOST")
    return if host.nil?
    return if forwarded_host.present? && canonical_public_host(forwarded_host) != host

    "https://#{host}"
  end

  def canonical_public_host(value)
    return if value.blank? || value.include?(",")

    normalized = value.downcase
    normalized = normalized.delete_suffix(":443")
    ISSUER_HOSTS.include?(normalized) ? normalized : nil
  end
end
