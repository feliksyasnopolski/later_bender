namespace :users do
  desc "Create a local user"
  task create: :environment do
    username = ENV.fetch("USERNAME") { abort "Usage: bin/rails users:create USERNAME=name PASSWORD=password" }
    password = ENV.fetch("PASSWORD") { abort "Usage: bin/rails users:create USERNAME=name PASSWORD=password" }
    user = User.create!(username: username, password: password, password_confirmation: password)
    puts "Created user #{user.username} (id=#{user.id})"
  end
end
