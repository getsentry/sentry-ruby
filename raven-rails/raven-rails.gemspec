$:.unshift File.expand_path('../lib', __FILE__)
require 'raven/rails/version'

Gem::Specification.new do |gem|
  gem.name = "raven-rails"
  gem.version = Raven::Rails::VERSION
  gem.platform = Gem::Platform::RUBY
  gem.summary = "Integrate Rails error handling with the Sentry error logger"
  gem.email = "noah@coderanger.net"
  gem.homepage = "http://github.com/coderanger/raven-ruby"
  gem.authors = ["Noah Kantrowitz"]
  gem.has_rdoc = true
  gem.extra_rdoc_files = ["README.md", "LICENSE"]
  gem.files = Dir['lib/**/*']
  gem.add_dependency "raven"
end
