source "https://rubygems.org/"
git_source(:github) { |name| "https://github.com/#{name}.git" }

gemspec

rails_version = ENV["RAILS_VERSION"]
rails_version = "5.2" if rails_version.nil?

if rails_version.to_f != 0
  gem "rails", "~> #{rails_version}"
  gem "rspec-rails", "~> 4.0"
end

gem "delayed_job"
gem "sidekiq", "< 7.0"

gem "rack", "< 3.0"
gem "rack-timeout"

# TODO: Remove this if https://github.com/jruby/jruby/issues/6547 is addressed
gem "i18n", "<= 1.8.7"

gem "pry"
gem "benchmark-ips"
gem "benchmark_driver"
gem "benchmark-ipsa"
gem "benchmark-memory"
gem "ruby-prof", platform: :mri
gem "rake", "> 12"
gem "rspec", "~> 3.9.0"
gem "capybara", "~> 3.15.0" # rspec system tests
gem "puma" # rspec system tests

# https://github.com/flavorjones/loofah/pull/267
# loofah changed the required ruby version in a patch so we need to explicitly pin it
gem "loofah", "2.20.0" if RUBY_VERSION.to_f < 2.5

gem "timecop"
gem "test-unit"
gem "simplecov"
gem "codecov", "<= 0.2.12"
