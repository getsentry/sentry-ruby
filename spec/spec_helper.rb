# frozen_string_literal: true

require "sentry-ruby"
require "sentry/test_helper"

require "selenium-webdriver"

require "capybara"
require "capybara/rspec"
require "debug"

require_relative "support/test_helper"

Capybara.configure do |config|
  config.default_driver = :selenium_headless_chrome
  config.javascript_driver = :selenium_headless_chrome
  config.app_host = ENV.fetch("SENTRY_E2E_SVELTE_APP_URL", "http://localhost:4001")
  # The Svelte app is served by Vite, which compiles modules on demand on
  # the first request, and the Rails app's first request is also cold. Give
  # assertions enough time to absorb that one-time latency instead of
  # flaking on the first interaction of a run.
  config.default_max_wait_time = 10
end

Capybara.register_driver :selenium_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new

  options.add_argument("--headless")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--temp-profile")

  chromium_path = ENV.fetch("SENTRY_E2E_CHROME", "/usr/bin/chromium")
  options.binary = chromium_path if File.exist?(chromium_path)

  # Use a local chromedriver if provided, bypassing Selenium Manager's
  # download (which only ships an x86 driver and fails on arm64).
  chromedriver_path = ENV.fetch("SENTRY_E2E_CHROMEDRIVER", "/usr/bin/chromedriver")
  service = File.exist?(chromedriver_path) ? Selenium::WebDriver::Service.chrome(path: chromedriver_path) : nil

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

RSpec.configure do |config|
  config.include(Capybara::DSL, type: :e2e)
  config.include(Test::Helper)

  config.before(:suite) do
    Test::Helper.perform_basic_setup do |config|
      config.transport.transport_class = Sentry::DebugTransport
      config.enable_logs = true
      config.structured_logging.logger_class = Sentry::DebugStructuredLogger
      config.structured_logging.file_path = Test::Helper.debug_log_path.join("sentry_e2e_tests.log")
    end

    Test::Helper.clear_logged_events
  end

  config.after(:each) do
    Test::Helper.clear_logged_events
  end

  config.after(:each) do
    Test::Helper.clear_logs
  end
end
