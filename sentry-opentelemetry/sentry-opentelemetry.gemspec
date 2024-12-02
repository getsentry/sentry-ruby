# frozen_string_literal: true

require_relative "lib/sentry/opentelemetry/version"

Gem::Specification.new do |spec|
  spec.name          = "sentry-opentelemetry"
  spec.version       = Sentry::OpenTelemetry::VERSION
  spec.authors = ["Sentry Team"]
  spec.description = spec.summary = "A gem that provides OpenTelemetry integration for the Sentry error logger"
  spec.email = "accounts@sentry.io"
  spec.license = 'MIT'

  spec.platform = Gem::Platform::RUBY
  spec.required_ruby_version = '>= 2.4'
  spec.extra_rdoc_files = ["README.md", "LICENSE.txt"]
  spec.files = `git ls-files | grep -Ev '^(spec|benchmarks|examples|\.rubocop\.yml)'`.split("\n")

  github_root_uri = 'https://github.com/getsentry/sentry-ruby'
  spec.homepage = "#{github_root_uri}/tree/#{spec.version}/#{spec.name}"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{github_root_uri}/blob/#{spec.version}/CHANGELOG.md",
    "bug_tracker_uri" => "#{github_root_uri}/issues",
    "documentation_uri" => "http://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  }

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sentry-ruby", "~> 5.21.0"
  spec.add_dependency "opentelemetry-sdk", "~> 1.0"
end
