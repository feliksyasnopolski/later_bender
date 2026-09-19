module Api
  class CredentialsController < BaseController
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: { code: "credential_not_found", message: "Credential not found" } }, status: :not_found
    end
    before_action :set_credential, only: %i[show update destroy]

    def index
      scope = current_user.credentials.order(:created_at, :id)
      scope = scope.where(kind: params[:kind]) if params[:kind].present?
      render json: { credentials: scope.limit(params.fetch(:limit, 100).to_i.clamp(1, 100)).map { |c| metadata(c) }, next_cursor: nil }
    end

    def show = render json: metadata(@credential)

    def create
      credential = current_user.credentials.create!(credential_params)
      render json: metadata(credential), status: :created
    rescue ActiveRecord::RecordNotUnique
      render json: { error: { code: "credential_conflict", message: "Credential name is already in use" } }, status: :unprocessable_content
    end

    def update
      @credential.update!(credential_params)
      render json: metadata(@credential)
    rescue ActiveRecord::RecordNotUnique
      render json: { error: { code: "credential_conflict", message: "Credential name is already in use" } }, status: :unprocessable_content
    end

    def destroy
      @credential.destroy!
      render json: { ref: @credential.ref, destroyed: true }
    end

    private

    def set_credential = @credential = current_user.credentials.find_by!(ref: params[:id])
    def credential_params = params.permit(:name, :kind, :env_name, :file_path, :file_mode, :secret)
    def metadata(credential) = credential.metadata.merge("created_at" => credential.created_at, "updated_at" => credential.updated_at)
  end
end
