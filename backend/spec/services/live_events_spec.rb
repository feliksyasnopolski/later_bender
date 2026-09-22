require "rails_helper"

RSpec.describe LiveEvents do
  let(:user) { create(:user) }

  around do |example|
    original_url = ENV["REDIS_URL"]
    ENV.delete("REDIS_URL") unless example.metadata[:redis]
    described_class.shutdown!
    example.run
  ensure
    described_class.shutdown!
    ENV["REDIS_URL"] = original_url
  end

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

  it "fans out a published event through Redis when configured", :redis do
    skip "REDIS_URL is required for the Redis integration check" unless ENV["REDIS_URL"]

    queue = described_class.subscribe(user.id)
    publisher = Redis.new(url: ENV.fetch("REDIS_URL"))
    Timeout.timeout(2) do
      sleep 0.01 until publisher.pubsub("numsub", LiveEvents::CHANNEL).last.to_i.positive?
    end
    publisher.publish(
      LiveEvents::CHANNEL,
      JSON.generate("user_id" => user.id, "event" => { "type" => "task.updated", "ref" => "LB-109" })
    )

    expect(Timeout.timeout(2) { queue.pop }.json).to eq(
      { "type" => "task.updated", "ref" => "LB-109" }.to_json
    )
    described_class.unsubscribe(user.id, queue)
  ensure
    described_class.shutdown!
  end

  it "keeps the canonical mutation path working when Redis is unavailable", :redis do
    skip "REDIS_URL is required for the Redis outage check" unless ENV["REDIS_URL"]

    queue = described_class.subscribe(user.id)
    allow(described_class).to receive(:redis).and_raise(Redis::CannotConnectError)

    described_class.publish(user:, type: "note.updated", ref: "50")

    expect(queue.pop.json).to eq({ "type" => "note.updated", "ref" => "50" }.to_json)
    described_class.unsubscribe(user.id, queue)
  ensure
    described_class.shutdown!
  end

  it "keeps Redis delivery user-scoped", :redis do
    skip "REDIS_URL is required for the Redis integration check" unless ENV["REDIS_URL"]

    other = create(:user)
    queue = described_class.subscribe(user.id)
    publisher = Redis.new(url: ENV.fetch("REDIS_URL"))
    Timeout.timeout(2) do
      sleep 0.01 until publisher.pubsub("numsub", LiveEvents::CHANNEL).last.to_i.positive?
    end
    publisher.publish(
      LiveEvents::CHANNEL,
      JSON.generate("user_id" => other.id, "event" => { "type" => "task.updated", "ref" => "LB-other" })
    )

    sleep 0.1
    expect(queue).to be_empty
    described_class.unsubscribe(user.id, queue)
  ensure
    described_class.shutdown!
  end
end
