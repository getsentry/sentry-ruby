$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'raven/version'

Gem::Specification.new do |gem|
  gem.name = "sentry-raven"
  gem.version = Raven::VERSION
  gem.platform = Gem::Platform::RUBY
  gem.description = gem.summary = "A gem that provides a client interface for the Sentry error logger"
  gem.email = "getsentry@googlegroups.com"
  gem.homepage = "https://github.com/getsentry/raven-ruby"
  gem.authors = ["Sentry Team"]
  gem.has_rdoc = true
  gem.extra_rdoc_files = ["README.md", "LICENSE"]
  gem.files = Dir['lib/**/*']
  gem.executables = gem.files.grep(%r{^exe/}) { |f| File.basename(f) }
  gem.license = 'Apache-2.0'
  gem.required_ruby_version = '>= 1.9.0'

  gem.add_dependency "faraday", ">= 0.7.6", "< 1.0"

  gem.add_development_dependency "rake"
  gem.add_development_dependency "rubocop", "~> 0.41.1"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "rspec-rails"
  gem.add_development_dependency "timecop"
  gem.add_development_dependency "test-unit" if RUBY_VERSION > '2.2'
end
