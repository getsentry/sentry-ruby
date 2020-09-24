Rails.application.routes.draw do
  get '500', :to => 'welcome#report_demo'
  root to: "welcome#index"

  get 'view_error', to: 'welcome#view_error'

  require 'sidekiq/web'

  mount Sidekiq::Web => '/sidekiq'
end
