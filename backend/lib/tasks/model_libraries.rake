namespace :model_libraries do
  desc "Sync the source-controlled Code Mode lb library for one user with an explicit revision precondition"
  task sync_standard: :environment do
    user_id = ENV.fetch("USER_ID") { abort "USER_ID is required" }
    expected_revision = Integer(ENV.fetch("EXPECTED_REVISION") { abort "EXPECTED_REVISION is required (use 0 only to create)" }, 10)
    source_path = Rails.root.join("config", "standard_library", "lb.js")
    abort "Source library not found: #{source_path}" unless source_path.file?

    user = User.find(user_id)
    ModelLibrary.transaction do
      library = user.model_libraries.lock.find_by(name: "lb")
      current_revision = library&.revision || 0
      abort "Revision conflict: expected #{expected_revision}, current revision is #{current_revision}" unless expected_revision == current_revision

      source = source_path.read
      if library
        library.versions = (library.versions + [ { revision: library.revision, source: library.source, description: library.description, exports: library.exports } ]).last(10)
        library.update!(source: source, description: "Source-controlled Later Bender Code Mode helpers", exports: %w[call context execution memory], revision: library.revision + 1)
      else
        user.model_libraries.create!(name: "lb", source: source, description: "Source-controlled Later Bender Code Mode helpers", exports: %w[call context execution memory], revision: 1)
      end
      puts "Synced lb for user #{user.id} at revision #{library ? library.revision : 1}"
    end
  end
end
