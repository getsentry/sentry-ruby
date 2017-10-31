require "minitest/autorun"
require "minitest/proveit"
require "minitest/parallel"

require "sentry-raven-without-integrations"
require "raven/transports/dummy"

Raven.configure do |config|
  config.dsn = "dummy://12345:67890@sentry.localdomain/sentry/42"
  config.encoding = "json"
  config.silence_ready = true
  config.logger = Logger.new(nil)
end

class Raven::ThreadUnsafeTest < Minitest::Test
  class << self
    # Ripped from Minitest::Spec
    def it(desc = "anonymous", &block)
      block ||= proc { skip "(no tests defined)" }

      @specs ||= 0
      @specs += 1

      name = format("test_%04d_%s", @specs, desc)

      define_method name, &block

      name
    end

    def children
      @children ||= []
    end
  end
end

class Raven::Test < Raven::ThreadUnsafeTest
  parallelize_me!
end
