FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "factory-user-#{n}" }
    password { "password123" }
  end
end
