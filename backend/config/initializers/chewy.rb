Chewy.root_strategy = Rails.env.test? ? :bypass : :urgent
Chewy.request_strategy = Rails.env.test? ? :bypass : :atomic
Chewy.use_after_commit_callbacks = true
