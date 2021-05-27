require_relative "lib/sentry/lambda/version"

Gem::Specification.new do |spec|
  spec.name          = "sentry-lambda"
  spec.version       = Sentry::Lambda::VERSION
  spec.authors = ["Sentry Team"]
  spec.description = spec.summary = "A gem that provides AWS Lambda integration for the Sentry error logger"
  spec.email = "accounts@sentry.io"
  spec.license = 'Apache-2.0'
  spec.homepage = "https://github.com/getsentry/sentry-ruby"

  spec.platform = Gem::Platform::RUBY
  spec.required_ruby_version = '>= 2.4'
  spec.extra_rdoc_files = ["README.md", "LICENSE.txt"]
  spec.files = Dir['lib/**/*.rb']

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/sentry-lambda/CHANGELOG.md"

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sentry-ruby-core", "~> 4.4.0.pre.beta"
end
