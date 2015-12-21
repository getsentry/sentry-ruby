$:.unshift File.expand_path('../lib', __FILE__)
require 'raven/version'

Gem::Specification.new do |gem|
  gem.name = "sentry-raven"
  gem.version = Raven::VERSION
  gem.executables << "raven"
  gem.platform = Gem::Platform::RUBY
  gem.description = gem.summary = "A gem that provides a client interface for the Sentry error logger"
  gem.email = "getsentry@googlegroups.com"
  gem.homepage = "https://github.com/getsentry/raven-ruby"
  gem.authors = ["Sentry Team"]
  gem.has_rdoc = true
  gem.extra_rdoc_files = ["README.md", "LICENSE"]
  gem.files = Dir['lib/**/*']
  gem.license = 'Apache-2.0'
  gem.required_ruby_version = '>= 1.8.7'

  gem.add_dependency "faraday", ">= 0.7.6"

  gem.add_development_dependency "rake"
  gem.add_development_dependency "rubocop" if RUBY_VERSION > '1.8.7'
  gem.add_development_dependency "rspec", "~> 3.0"
  gem.add_development_dependency "rspec-rails"
  gem.add_development_dependency "mime-types", "~> 1.16"
  gem.add_development_dependency "rest-client", "< 1.7.0" if RUBY_VERSION == '1.8.7'
  gem.add_development_dependency "rest-client" if RUBY_VERSION > '1.8.7'
  gem.add_development_dependency "timecop", "0.6.1" if RUBY_VERSION == '1.8.7'
  gem.add_development_dependency "timecop" if RUBY_VERSION > '1.8.7'
end
