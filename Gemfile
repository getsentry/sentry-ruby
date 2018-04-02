source "https://rubygems.org/"

gemspec

if ENV["RAILS_VERSION"] && (ENV["RAILS_VERSION"].to_i == 4)
  gem "rails", "< 5"
  gem "rspec-rails"
elsif ENV["RAILS_VERSION"] && (ENV["RAILS_VERSION"].to_i == 0)
  # no-op. No Rails.
else
  gem "rails", "< 6"
  gem "rspec-rails"
end

gem "rack"
gem "sidekiq"
gem "rack-timeout"
gem "pry"
gem "pry-coolline"
gem "benchmark-ips"
gem "benchmark-ipsa"
gem "ruby-prof", platform: :mri
gem "rake"
gem "minitest-proveit"
gem "rubocop", "~> 0.41.1"
gem "rspec"
gem "capybara" # rspec system tests
gem "puma" # rspec system tests

gem "timecop"
gem "test-unit", platform: :mri if RUBY_VERSION > '2.2'
