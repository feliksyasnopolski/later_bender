module Api
  class TotpController < BaseController
    def index
      render json: { credentials: current_user.totp_credentials.where.not(confirmed_at: nil).order(:created_at).map { |credential| serialize(credential) } }
    end

    def create
      return render json: { error: "Current password is required" }, status: :unauthorized unless current_user.valid_password?(request_payload["password"].to_s)

      credential = current_user.totp_credentials.create!(label: request_payload["label"].to_s.presence || "Authenticator", secret: ROTP::Base32.random)
      uri = ROTP::TOTP.new(credential.secret, issuer: "Later, Bender", period: 30, digits: 6).provisioning_uri(current_user.username)
      qr = RQRCode::QRCode.new(uri).as_svg(module_size: 5, standalone: true)
      render json: { credential: { id: credential.id, label: credential.label }, secret: credential.secret, provisioning_uri: uri, qr_svg_base64: Base64.strict_encode64(qr) }, status: :created
    rescue ActiveRecord::RecordInvalid => error
      render_errors(error.record)
    end

    def confirm
      credential = current_user.totp_credentials.find_by(id: params[:id])
      return render_not_found unless credential
      return render json: { error: "Current password and code are required" }, status: :unauthorized unless current_user.valid_password?(request_payload["password"].to_s)
      return render json: { error: "Invalid authenticator code" }, status: :unprocessable_entity unless credential.verify(request_payload["code"])

      credential.update!(confirmed_at: Time.current)
      render json: { credential: serialize(credential) }
    end

    def destroy
      credential = current_user.totp_credentials.find_by(id: params[:id])
      return render_not_found unless credential
      return render json: { error: "Current password is required" }, status: :unauthorized unless current_user.valid_password?(request_payload["password"].to_s)

      credential.destroy!
      head :no_content
    end

    private

    def serialize(credential)
      { id: credential.id, label: credential.label, created_at: credential.created_at }
    end
  end
end
