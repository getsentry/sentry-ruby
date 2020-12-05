# Sinatra Example For Sentry's Ruby SDK

## Setup

1. `bundle install`
2. Set your own Sentry DSN in `app.rb`

## Send Some Events To Sentry

### Exception & Performance Monitoring

1. Start the server - `bundle exec ruby app.rb`
2. Visit `localhost:4567/exception`
3. You should see both exception and transaction events in Sentry.

