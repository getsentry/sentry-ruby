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

if RUBY_VERSION < '2.0'
  gem "mime-types", "< 3.0.0"
  gem "nokogiri", "~> 1.6.8"
  gem "rack", "~> 1.6.8"
  gem "sidekiq", "< 3.2"
  gem "rack-timeout", "0.3.0"
else
  gem "rack"
  gem "sidekiq"
  gem "rack-timeout"
end
gem "pry"
gem "pry-coolline"
gem "benchmark-ips"
gem "benchmark-ipsa" if RUBY_VERSION > '2.0'
gem "ruby-prof", platform: :mri
gem "rake", "> 12"
gem "rubocop", "~> 0.41.1" # Last version that supported 1.9, upgrade to 0.50 after we drop 1.9
gem "rspec", "> 3"
gem "capybara" # rspec system tests
gem "puma" # rspec system tests

gem "timecop"
gem "test-unit", platform: :mri if RUBY_VERSION > '2.2'
