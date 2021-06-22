Rails.application.routes.draw do
  resources :posts
  get '500', :to => 'welcome#report_demo'
  root to: "welcome#index"

  get 'connect_trace', to: 'welcome#connect_trace'
  get 'view_error', to: 'welcome#view_error'
  get 'sidekiq_error', to: 'welcome#sidekiq_error'
  get 'job_error', to: 'welcome#job_error'

  require 'sidekiq/web'

  mount Sidekiq::Web => '/sidekiq'
end
