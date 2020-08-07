source "https://rubygems.org/"

gemspec

if ENV["RAILS_VERSION"] && (ENV["RAILS_VERSION"].to_i == 4)
  gem "rails", "< 5"
  gem "rspec-rails", "> 3"
elsif ENV["RAILS_VERSION"] && (ENV["RAILS_VERSION"].to_i == 0)
  # no-op. No Rails.
else
  gem "rails", "< 6"
  gem "rspec-rails", "> 3"
end

gem "rack"
gem "rack-timeout"

if ENV["SIDEKIQ_VERSION"].to_i >= 6 && RUBY_VERSION > '2.5'
  gem "sidekiq", ">= 6"
else
  gem "sidekiq", "< 6"
end

gem "pry"
gem "benchmark-ips"
gem "benchmark-ipsa"
gem "ruby-prof", platform: :mri
gem "rake", "> 12"
gem "rubocop", "~> 0.41.1" # Last version that supported 1.9, upgrade to 0.50 after we drop 1.9
gem "rspec", "> 3"
gem "capybara" # rspec system tests
gem "puma" # rspec system tests

gem "timecop"
gem "test-unit"
gem "simplecov"
