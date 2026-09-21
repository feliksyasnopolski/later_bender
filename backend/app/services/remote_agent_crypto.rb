module RemoteAgentCrypto
  class InvalidSignature < StandardError; end

  module_function

  def signed_bytes(agent_ref, challenge_id, nonce, expires_at)
    "later-bender-agent-auth-v1\n#{agent_ref}\n#{challenge_id}\n#{nonce}\n#{expires_at.utc.iso8601(6)}"
  end

  def verify!(public_key, encoded_signature, bytes)
    signature = Base64.strict_decode64(encoded_signature.to_s)
    raise InvalidSignature unless signature.bytesize == Ed25519::SIGNATURE_SIZE

    Ed25519::VerifyKey.new(Base64.strict_decode64(public_key)).verify(signature, bytes)
  rescue ArgumentError, TypeError, Ed25519::VerifyError
    raise InvalidSignature
  end
end
