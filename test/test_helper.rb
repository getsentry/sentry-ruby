require "minitest/autorun"
require "minitest/proveit"
require "minitest/parallel"

require "sentry-raven-without-integrations"
require "raven/transports/dummy"

class Raven::ThreadUnsafeTest < Minitest::Test
  class << self
    def it desc = "anonymous", &block
      block ||= proc { skip "(no tests defined)" }

      @specs ||= 0
      @specs += 1

      name = "test_%04d_%s" % [ @specs, desc ]

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
