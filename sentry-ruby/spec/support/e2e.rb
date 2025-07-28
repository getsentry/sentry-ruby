# frozen_string_literal: true

require "capybara"
require "capybara/rspec"
require "selenium-webdriver"

module E2ETestHelper
  def self.setup_capybara
    Capybara.configure do |config|
      config.default_driver = :selenium_headless_chrome
      config.javascript_driver = :selenium_headless_chrome
      config.app_host = "http://localhost:5001"
    end

    Capybara.register_driver :selenium_headless_chrome do |app|
      options = Selenium::WebDriver::Chrome::Options.new

      options.add_argument("--headless")
      options.add_argument("--disable-dev-shm-usage")
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-gpu")
      options.add_argument("--temp-profile")

      Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
    end
  end
end
