# Rails 6 Example For Sentry's Ruby SDK

## Setup

1. `bundle install`
2. Set your own Sentry DSN in `config/application.rb`

## Send Some Events To Sentry

### Normal Rails Exception

1. Start the Rails server - `bundle exec rails s`
2. Visit `localhost:3000/`

### Rails View Exception

1. Start the Rails server - `bundle exec rails s`
2. Visit `localhost:3000/view_error`

### Sidekiq Worker Exception

1. Start `sidekiq` server - `bundle exec sidekiq`
2. Run the job with Rails runner - `bundle exec rails runner "ErrorWorker.perform_async"`
