source "https://rubygems.org/"

gemspec

rails_version = ENV["RAILS_VERSION"].to_f

if rails_version != 0
  gem "rails", "~> #{rails_version}"
  gem "rspec-rails", "~> 4.0"
end

gem "sidekiq"

gem "rack"
gem "rack-timeout"

gem "pry"
gem "benchmark-ips"
gem "benchmark_driver"
gem "benchmark-ipsa"
gem "benchmark-memory"
gem "ruby-prof", platform: :mri
gem "rake", "> 12"
gem "rubocop", "~> 0.81.0"
gem "rspec", "~> 3.9.0"
gem "capybara", "~> 3.15.0" # rspec system tests
gem "puma" # rspec system tests

gem "timecop"
gem "test-unit"
gem "simplecov"
gem "codecov"
