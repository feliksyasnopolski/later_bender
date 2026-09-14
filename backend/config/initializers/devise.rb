require "devise"
require "devise/orm/active_record"

Devise.setup do |config|
  config.secret_key = Rails.application.secret_key_base
  config.stretches = 12
  config.authentication_keys = [ :username ]
  config.case_insensitive_keys = [ :username ]
  config.strip_whitespace_keys = [ :username ]
end
