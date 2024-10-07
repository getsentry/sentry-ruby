# frozen_string_literal: true

eval_gemfile File.expand_path("Gemfile", __dir__)

gem "sentry-rails", path: "../sentry-rails"
gem "rails"
