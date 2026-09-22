Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, controllers: { sessions: "users/sessions" }, skip: %i[registrations passwords]

  use_doorkeeper
  get "/.well-known/oauth-authorization-server", to: "oauth_metadata#show"
  post "/oauth/register", to: "oauth_registration#create"

  namespace :api do
    post "auth/login", to: "auth#login"
    get "auth/current", to: "auth#current"
    get "search", to: "search#index"
    get "workspaces/capabilities", to: "workspaces#capabilities"
    get "workspaces/targets", to: "workspaces#targets"
    post "remote-agents/enrollment-tokens", to: "remote_agents#enrollment_token"
    get "remote-agents", to: "remote_agents#index"
    patch "remote-agents/:ref", to: "remote_agents#update"
    post "remote-agents/:ref/revoke", to: "remote_agents#revoke"
    post "remote-agent/enroll", to: "remote_agent_protocol#enroll"
    post "remote-agent/challenge", to: "remote_agent_protocol#challenge"
    post "remote-agent/authenticate", to: "remote_agent_protocol#authenticate"
    get "remote-agent/stream", to: "remote_agent_protocol#stream"
    post "remote-agent/heartbeat", to: "remote_agent_protocol#heartbeat"
    get "remote-agent/operations", to: "remote_agent_protocol#operations"
    post "remote-agent/operations/:operation_id/result", to: "remote_agent_protocol#operation_result"
    resources :credentials, only: %i[index create show update destroy]
    resources :workspaces, only: %i[index create]
    get "workspaces/:ref", to: "workspaces#show"
    delete "workspaces/:ref", to: "workspaces#destroy"
    post "workspaces/:ref/files", to: "workspaces#put_file"
    post "workspaces/:ref/file-read", to: "workspaces#read_file"
    post "workspaces/:ref/file-promote", to: "workspaces#promote_file"
    post "workspaces/:ref/executions", to: "workspaces#execute"
    get "workspaces/:ref/executions/:execution_ref", to: "workspaces#execution"
    post "workspaces/:ref/executions/:execution_ref/output", to: "workspaces#output"
    post "workspaces/:ref/executions/:execution_ref/cancel", to: "workspaces#cancel"
    post "workspaces/:ref/transcript", to: "workspaces#transcript"
    post "workspaces/:ref/transcript-promote", to: "workspaces#promote_transcript"
    get "workspace-executions/:ref", to: "workspaces#execution_by_ref"
    post "workspace-executions/:ref/output", to: "workspaces#output_by_ref"
    post "workspace-executions/:ref/cancel", to: "workspaces#cancel_by_ref"
    get "oauth/token_info", to: "oauth#token_info"
    delete "auth/logout", to: "auth#logout"
    post "auth/recover", to: "auth#recover"
    resources :tokens, only: %i[index create destroy]
    get "account/totp", to: "totp#index"
    post "account/totp", to: "totp#create"
    post "account/totp/:id/confirm", to: "totp#confirm"
    delete "account/totp/:id", to: "totp#destroy"
    resources :projects, param: :slug, only: %i[index show create update] do
      resources :tasks, only: %i[index show create update destroy]
      resources :notes, only: %i[index create]
      resources :files, only: %i[index create]
    end
    resources :tasks, only: :index
    get "tasks/:id", to: "tasks#show"
    patch "tasks/:id", to: "tasks#update"
    get "tasks/by-ref/:ref", to: "tasks#show_by_ref"
    patch "tasks/by-ref/:ref", to: "tasks#update_by_ref"
    get "files/by-ref/:ref", to: "files#show"
    patch "files/by-ref/:ref", to: "files#update"
    delete "files/by-ref/:ref", to: "files#destroy"
    get "files/by-ref/:ref/read", to: "files#read"
    post "files/by-ref/:ref/read-batch", to: "files#read_batch"
    get "files/by-ref/:ref/egress", to: "files#egress"
    get "files/by-ref/:ref/download", to: "files#download"
    get "files/by-ref/:ref/archive", to: "files#archive_list"
    get "files/by-ref/:ref/archive/entry", to: "files#archive_entry"
    post "files/by-ref/:ref/archive/extract", to: "files#archive_extract"
    resources :notes, only: %i[index show create update destroy] do
      patch :edit, on: :member
    end
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
