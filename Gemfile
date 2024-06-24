source "https://rubygems.org"
git_source(:github) { |name| "https://github.com/#{name}.git" }

gem "rake", "~> 12.0"

ruby_version = Gem::Version.new(RUBY_VERSION)

# Development tools
if ruby_version >= Gem::Version.new("2.7.0")
  gem "debug", github: "ruby/debug", platform: :ruby
  gem "irb"
  gem "ruby-lsp-rspec" if ruby_version >= Gem::Version.new("3.0.0") && RUBY_PLATFORM != "java"
end

# For RSpec
gem "rspec", "~> 3.0"
gem "rspec-retry"
gem "simplecov"
gem "simplecov-cobertura", "~> 1.4"
gem "rexml"

gem "rubocop-rails-omakase"
