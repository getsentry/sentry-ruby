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
end

Capybara.register_driver :selenium_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new

  options.add_argument("--headless")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--temp-profile")
  options.binary = "/usr/bin/chromium" if File.exist?("/usr/bin/chromium")

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure do |config|
  config.include(Capybara::DSL, type: :e2e)
  config.include(Test::Helper)

  config.before(:suite) do
    Test::Helper.perform_basic_setup do |config|
      config.transport.transport_class = Sentry::DebugTransport
      config.structured_logger_class = Sentry::DebugStructuredLogger
      config.sdk_debug_structured_logger_log_file = Test::Helper.debug_log_path.join("sentry_e2e_tests.log")
      config.enable_logs = true
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
