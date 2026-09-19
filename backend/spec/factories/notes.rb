FactoryBot.define do
  factory :note do
    association :user
    sequence(:title) { |n| "Factory note #{n}" }
    body { "factory note body" }
  end
end
