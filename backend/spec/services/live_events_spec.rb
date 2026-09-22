require "rails_helper"

RSpec.describe LiveEvents do
  let(:user) { create(:user) }

  it "delivers compact user-scoped events and removes subscriptions" do
    queue = described_class.subscribe(user.id)
    described_class.publish(user:, type: "task.updated", ref: "LB-106")

    event = queue.pop
    expect(event.json).to eq({ "type" => "task.updated", "ref" => "LB-106" }.to_json)
    expect(event.json).not_to include("secret", "password", "token")

    described_class.unsubscribe(user.id, queue)
    described_class.publish(user:, type: "task.updated", ref: "LB-107")
    expect(queue.empty?).to be(true)
  end

  it "does not cross user boundaries" do
    other = create(:user)
    queue = described_class.subscribe(user.id)
    described_class.publish(user: other, type: "note.updated", ref: "50")
    expect(queue.empty?).to be(true)
    described_class.unsubscribe(user.id, queue)
  end
end
