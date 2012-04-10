$:.unshift File.expand_path('../lib', __FILE__)
require 'raven/version'

Gem::Specification.new do |gem|
  gem.name = "raven"
  gem.version = Raven::VERSION
  gem.platform = Gem::Platform::RUBY
  gem.summary = "A gem that provides a client interface for the Sentry error logger"
  gem.email = "noah@coderanger.net"
  gem.homepage = "http://github.com/coderanger/raven-ruby"
  gem.authors = ["Noah Kantrowitz"]
  gem.has_rdoc = true
  gem.extra_rdoc_files = ["README.md", "LICENSE"]
  gem.files = Dir['lib/**/*']
  gem.add_dependency "faraday", "~> 0.8.0.rc2"
  gem.add_dependency "uuidtools"
  gem.add_dependency "yajl-ruby"
  gem.add_dependency "hashie"
end
