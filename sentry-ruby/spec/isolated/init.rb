# frozen_string_literal: true

require_relative "../spec_helper"

Sentry.init do |config|
  config.dsn = Sentry::TestHelper::DUMMY_DSN
end

trap('HUP') do
  hub = Sentry.get_main_hub
  puts hub.class
end

Process.kill('HUP', Process.pid)
