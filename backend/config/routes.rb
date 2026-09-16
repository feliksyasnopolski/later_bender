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
    end
    resources :tasks, only: :index
    get "tasks/:id", to: "tasks#show"
    patch "tasks/:id", to: "tasks#update"
    get "tasks/by-ref/:ref", to: "tasks#show_by_ref"
    patch "tasks/by-ref/:ref", to: "tasks#update_by_ref"
    resources :notes, only: %i[index show create update]
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
