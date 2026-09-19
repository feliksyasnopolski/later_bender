require "rails_helper"

RSpec.describe Credential do
  let(:user) { create(:user) }

  it "assigns a stable per-user ref and encrypts the secret" do
    credential = user.credentials.create!(name: "Deploy token", kind: "env", env_name: "DEPLOY_TOKEN", secret: "sentinel-secret")
    expect(credential.ref).to eq("CRED-1")
    expect(credential.metadata).not_to have_key("secret")
    raw_secret = Credential.connection.select_value("SELECT secret FROM credentials WHERE id = #{credential.id}")
    expect(raw_secret).not_to eq("sentinel-secret")
    expect(credential.secret).to eq("sentinel-secret")
  end

  it "rejects unsafe file metadata" do
    credential = user.credentials.build(name: "Key", kind: "file", file_path: "/workspace/key", file_mode: 600, secret: "key")
    expect(credential).not_to be_valid
    expect(credential.errors[:file_path]).to be_present
  end

  it "does not allow changing kind" do
    credential = user.credentials.create!(name: "Key", kind: "file", file_path: "/root/.ssh/id_ed25519", file_mode: 600, secret: "key")
    credential.kind = "env"
    expect(credential).not_to be_valid
  end
end
