$:.unshift File.expand_path('../lib', __FILE__)
require 'raven/version'

Gem::Specification.new do |gem|
  gem.name = "sentry-raven"
  gem.version = Raven::VERSION
  gem.executables << "raven"
  gem.platform = Gem::Platform::RUBY
  gem.summary = "A gem that provides a client interface for the Sentry error logger"
  gem.email = "noah@coderanger.net"
  gem.homepage = "http://github.com/getsentry/raven-ruby"
  gem.authors = ["Noah Kantrowitz", "David Cramer"]
  gem.has_rdoc = true
  gem.extra_rdoc_files = ["README.md", "LICENSE"]
  gem.files = Dir['lib/**/*']

  gem.add_dependency "faraday", ">= 0.7.6"
  gem.add_dependency "uuidtools"
  gem.add_dependency "multi_json", "~> 1.0"
  gem.add_dependency "hashie"

  gem.add_development_dependency "rake"
  gem.add_development_dependency "rspec", "~> 2.10"
  gem.add_development_dependency "simplecov"
end
