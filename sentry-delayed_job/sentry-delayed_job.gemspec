require_relative "lib/sentry/delayed_job/version"

Gem::Specification.new do |spec|
  spec.name          = "sentry-delayed_job"
  spec.version       = Sentry::DelayedJob::VERSION
  spec.authors = ["Sentry Team"]
  spec.description = spec.summary = "A gem that provides DelayedJob integration for the Sentry error logger"
  spec.email = "accounts@sentry.io"
  spec.license = 'MIT'
  spec.homepage = "https://github.com/getsentry/sentry-ruby"

  spec.platform = Gem::Platform::RUBY
  spec.required_ruby_version = '>= 2.4'
  spec.extra_rdoc_files = ["README.md", "LICENSE.txt"]
  spec.files = `git ls-files | grep -Ev '^(spec|benchmarks|examples)'`.split("\n")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sentry-ruby", "~> 5.17.3"
  spec.add_dependency "delayed_job", ">= 4.0"
end
