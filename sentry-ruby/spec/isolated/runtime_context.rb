# frozen_string_literal: true

require "sentry-ruby"
require "sentry/test_helper"

Sentry.init do |config|
  config.dsn = Sentry::TestHelper::DUMMY_DSN
  config.transport.transport_class = Sentry::DummyTransport
  config.background_worker_threads = 0
end

RubyVM::YJIT.enable

Sentry.capture_message("main thread")
Thread.new { Sentry.capture_message("new thread") }.join

Sentry.get_current_client.transport.events.each do |event|
  puts event.contexts.dig(:runtime, :version)
end
