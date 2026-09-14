key_generator = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base, iterations: 1000)
Rails.application.config.active_record.encryption.primary_key = key_generator.generate_key("later-bender-totp-primary", 32)
Rails.application.config.active_record.encryption.deterministic_key = key_generator.generate_key("later-bender-totp-deterministic", 32)
Rails.application.config.active_record.encryption.key_derivation_salt = "later-bender-totp-salt"
