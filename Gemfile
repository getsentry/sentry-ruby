# frozen_string_literal: true

eval_gemfile "Gemfile.dev"

group :e2e do
  gem "capybara"
  gem "selenium-webdriver"
end

group :sentry do
  gem "sentry-ruby", path: "sentry-ruby"
  gem "sentry-rails", path: "sentry-rails"
end
