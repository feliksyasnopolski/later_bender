require "rails_helper"

RSpec.describe "Live invalidation", type: :request do
  it "rejects unauthenticated subscriptions" do
    get "/api/live", headers: { "ACCEPT" => "text/event-stream" }
    expect(response).to have_http_status(:unauthorized)
  end
end
