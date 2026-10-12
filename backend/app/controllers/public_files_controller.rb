class PublicFilesController < ActionController::API
  def show
    return head :not_found unless request.host == public_host

    file = StoredFile.find_by!(public_token: params[:token])
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:")
    response.set_header("Referrer-Policy", "no-referrer")
    send_data file.original.download, type: "text/html", disposition: "inline", filename: file.filename
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def public_host
    URI.parse(ENV.fetch("PUBLIC_FILE_BASE_URL", request.base_url)).host
  end
end
