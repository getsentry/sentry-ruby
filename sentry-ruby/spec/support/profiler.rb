# frozen_string_literal: true

module ProfilerTest
  module Bar
    module Foo
      def self.foo
        1e6.to_i.times { 2**2 }
      end
    end

    def self.bar
      Foo.foo
      sleep 0.1
    end
  end
end
