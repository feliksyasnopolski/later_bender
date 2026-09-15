namespace :semantic_search do
  desc "Populate or repair semantic chunks from canonical Postgres records"
  task rebuild: :environment do
    SemanticIndexer.rebuild!
    puts "Semantic indexing complete"
  end
end
