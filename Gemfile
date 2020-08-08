source "https://rubygems.org/"

gemspec

if ENV["RAILS_VERSION"] && (ENV["RAILS_VERSION"].to_i == 4)
  gem "rails", "~> 4.2"
  gem "rspec-rails", "~> 4.0"
elsif ENV["RAILS_VERSION"] && (ENV["RAILS_VERSION"].to_i == 0)
  # no-op. No Rails.
else
  gem "rails", "~> 5.2"
  gem "rspec-rails", "~> 4.0"
end

gem "sidekiq"

gem "rack"
gem "rack-timeout"

gem "pry"
gem "benchmark-ips"
gem "benchmark-ipsa"
gem "ruby-prof", platform: :mri
gem "rake", "> 12"
gem "rubocop", "~> 0.41.1" # Last version that supported 1.9, upgrade to 0.50 after we drop 1.9
gem "rspec", "~> 3.9.0"
gem "capybara", "~> 3.15.0" # rspec system tests
gem "puma" # rspec system tests

gem "timecop"
gem "test-unit"
gem "simplecov"
gem "codecov"
