FactoryBot.define do
  factory :task do
    association :project
    sequence(:title) { |n| "Factory task #{n}" }
    status { "ready" }
    priority { "high" }
    context { "factory context" }
    intended_direction { "factory direction" }
  end
end
