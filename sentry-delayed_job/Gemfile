source "https://rubygems.org"

# Specify your gem's dependencies in sentry-ruby.gemspec
gemspec

# TODO: Remove this if https://github.com/jruby/jruby/issues/6547 is addressed
gem "i18n", "<= 1.8.7"

gem "rake", "~> 12.0"
gem "rspec", "~> 3.0"
gem 'simplecov'
gem "simplecov-cobertura", "~> 1.4"
gem "rexml"

gem "delayed_job"
gem "delayed_job_active_record"
gem "rails"
gem "activerecord-jdbcmysql-adapter", platform: :jruby
gem "jdbc-sqlite3", platform: :jruby
gem "sqlite3", platform: :ruby

gem "sentry-ruby", path: "../sentry-ruby"
gem "sentry-rails", path: "../sentry-rails"

gem "pry"
gem "debug", github: "ruby/debug", platform: :ruby if RUBY_VERSION.to_f >= 2.6
