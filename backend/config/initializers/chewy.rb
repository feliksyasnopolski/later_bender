search_indexing_disabled = ENV["DISABLE_SEARCH_INDEXING"] == "true"
Chewy.root_strategy = search_indexing_disabled || Rails.env.test? ? :bypass : :urgent
Chewy.request_strategy = search_indexing_disabled || Rails.env.test? ? :bypass : :atomic
Chewy.use_after_commit_callbacks = true
