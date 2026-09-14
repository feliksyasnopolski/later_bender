namespace :api_tokens do
  desc "Create an API token and print the raw token once"
  task create: :environment do
    name = ENV.fetch("NAME") { abort "Usage: bin/rails api_tokens:create NAME=client-name" }
    username = ENV.fetch("USERNAME") { abort "Usage: bin/rails api_tokens:create USERNAME=username NAME=client-name" }
    user = User.find_for_database_authentication(username: username)
    abort "Unknown username: #{username}" unless user
    _token, raw_token = ApiToken.issue!(user: user, name: name)
    puts "Token name: #{name}"
    puts "Bearer token (save it now; it will not be shown again): #{raw_token}"
  end
end
