require "resque/server"

Rails.application.routes.draw do
  resources :posts
  get '500', to: 'welcome#report_demo'
  root to: "welcome#index"

  get 'appearance', to: 'welcome#appearance'
  get 'connect_trace', to: 'welcome#connect_trace'
  get 'view_error', to: 'welcome#view_error'
  get 'sidekiq_error', to: 'welcome#sidekiq_error'
  get 'resque_error', to: 'welcome#resque_error'
  get 'delayed_job_error', to: 'welcome#delayed_job_error'
  get 'job_error', to: 'welcome#job_error'

  require 'sidekiq/web'

  mount Sidekiq::Web => '/sidekiq'
  mount Resque::Server.new, at: "/resque"
end
