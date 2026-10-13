# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "StreamingReporter"
rescue LoadError
end

require "shellwords"
require "sentry/rails/overrides/streaming_reporter"

RSpec.describe Sentry::Rails::Overrides::StreamingReporter do
  it "is prepended to ActionController::Live" do
    make_basic_app

    expect(ActionController::Live.ancestors).to include(described_class)
  end

  # rspec-rails loads ActionController::Live before the suite starts, so boot a
  # bare app in a child process to see what initialization alone loads.
  it "doesn't load ActionController::Live while the app initializes" do
    skip "Rails #{::Rails.version} has no :action_controller_live load hook" unless Sentry::Railtie::SUPPORTS_ACTION_CONTROLLER_LIVE_LOAD_HOOK

    script = <<~RUBY
      require "action_controller/railtie"
      require "sentry-rails"

      class LiveLoadApp < Rails::Application
        config.eager_load = false
        config.secret_key_base = "secret"
      end

      LiveLoadApp.initializer :sentry do
        Sentry.init do |config|
          config.dsn = "http://12345:67890@sentry.localdomain:3000/sentry/42"
          config.sdk_logger = Logger.new(nil)
          config.background_worker_threads = 0
        end
      end

      LiveLoadApp.initialize!
      # loading controllers must not drag ActionController::Live in with them
      ActionController::Base

      print ActionController.autoload?(:Live) ? "lazy" : "loaded"
    RUBY

    expect(`#{RbConfig.ruby} -e #{Shellwords.escape(script)}`.lines.last).to eq("lazy")
  end
end
