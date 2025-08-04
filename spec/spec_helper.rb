# frozen_string_literal: true

require "sentry-ruby"
require "sentry/test_helper"

require "selenium-webdriver"

require "capybara"
require "capybara/rspec"

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
end
