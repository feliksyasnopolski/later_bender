FactoryBot.define do
  factory :stored_file do
    association :project
    sequence(:filename) { |n| "factory-file-#{n}.txt" }
    media_type { "text/plain" }
    transient do
      contents { "factory file content" }
    end
    byte_size { contents.bytesize }
    sha256 { Digest::SHA256.hexdigest(contents) }

    after(:build) do |file, evaluator|
      file.original.attach(io: StringIO.new(evaluator.contents), filename: file.filename, content_type: file.media_type)
    end
  end
end
