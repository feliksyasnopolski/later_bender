FactoryBot.define do
  factory :project do
    association :user
    sequence(:name) { |n| "Factory Project #{n}" }
    sequence(:slug) { |n| "factory-project-#{n}" }
    sequence(:shorthand) { |n| "FP#{n}" }
  end
end
