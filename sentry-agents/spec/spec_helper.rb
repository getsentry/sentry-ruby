# frozen_string_literal: true

require "bundler/setup"
begin
  require "debug/prelude"
rescue LoadError
end

require "simplecov"

SimpleCov.start do
  project_name "sentry-agents"
  root File.join(__FILE__, "../../")
  coverage_dir File.join(__FILE__, "../coverage")
end

if ENV["CI"]
  require "simplecov-cobertura"
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require "sentry-ruby"
require "sentry/test_helper"
require "sentry-agents"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include(Sentry::TestHelper)

  config.after :each do
    reset_sentry_globals!
  end
end
