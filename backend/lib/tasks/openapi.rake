namespace :openapi do
  desc "Generate the checked-in browser API contract"
  task generate: :environment do
    Rake::Task["rswag:specs:swaggerize"].invoke
  end

  desc "Regenerate the browser API contract and fail when it changes"
  task check: :environment do
    Rake::Task["openapi:generate"].invoke
    require "openapi_parser"
    OpenAPIParser.load(Rails.root.join("openapi/v1.yaml").to_s, strict_reference_validation: true)
    unless system("git", "diff", "--quiet", "--", "openapi/v1.yaml")
      abort "openapi/v1.yaml is out of date; run bundle exec rake openapi:generate"
    end
  end
end
