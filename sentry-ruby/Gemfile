source "https://rubygems.org"
git_source(:github) { |name| "https://github.com/#{name}.git" }

gem "sentry-ruby", path: "./"

rack_version = ENV["RACK_VERSION"]
rack_version = "3.0.0" if rack_version.nil?
gem "rack", "~> #{Gem::Version.new(rack_version)}" unless rack_version == "0"

redis_rb_version = ENV.fetch("REDIS_RB_VERSION", "5.0")
gem "redis", "~> #{redis_rb_version}"

gem "puma"

gem "rake", "~> 12.0"
gem "rspec", "~> 3.0"
gem "rspec-retry"
gem "timecop"
gem "simplecov"
gem "simplecov-cobertura", "~> 1.4"
gem "rexml"
gem "stackprof" unless RUBY_PLATFORM == "java"

ruby_version = Gem::Version.new(RUBY_VERSION)

if ruby_version >= Gem::Version.new("2.6.0")
  gem "debug", github: "ruby/debug", platform: :ruby
  gem "irb"

  if ruby_version >= Gem::Version.new("3.0.0")
    gem "ruby-lsp-rspec"
  end
end

gem "pry"

gem "benchmark-ips"
gem "benchmark_driver"
gem "benchmark-ipsa"
gem "benchmark-memory"

gem "yard", github: "lsegal/yard"
gem "webrick"
