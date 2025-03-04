# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |name| "https://github.com/#{name}.git" }

gem "jar-dependencies" if RUBY_PLATFORM == "java"
gem "rake", "~> 12.0"

ruby_version = Gem::Version.new(RUBY_VERSION)

# Development tools
if ruby_version >= Gem::Version.new("2.7.0")
  gem "debug", github: "ruby/debug", platform: :ruby
  gem "irb"
  gem "ruby-lsp-rspec" if ruby_version >= Gem::Version.new("3.0.0") && RUBY_PLATFORM != "java"
end

# For RSpec
gem "rspec", "~> 3.13"
gem "rspec-retry", "~> 0.6"
gem "simplecov"
gem "simplecov-cobertura", "~> 2.1"
gem "rexml"

group :rubocop do
  gem "rubocop-rails-omakase"
  gem "rubocop-packaging"
end
