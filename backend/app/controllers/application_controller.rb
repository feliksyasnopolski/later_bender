class ApplicationController < ActionController::Base
  private

  def after_sign_in_path_for(_resource)
    return_to = session.delete(:oauth_return_to).to_s
    return return_to if return_to.start_with?("/oauth/authorize?")

    super
  end
end
