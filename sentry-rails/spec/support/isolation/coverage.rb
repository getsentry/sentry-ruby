# frozen_string_literal: true

require "json"
require_relative "../isolation"

module Test
  module Isolation
    module Coverage
      private

      def in_child
        ::Coverage.result(stop: false, clear: true)
        result = super
        { result: result, coverage: Coverage.measured_in_child }
      end

      def from_child(payload)
        Coverage.absorb(payload[:coverage])
        super(payload[:result])
      end

      class << self
        def measured_in_child
          root = SimpleCov.root
          project_files = ::Coverage.result(stop: false, clear: true).select { |file, _| file.start_with?(root) }
          JSON.parse(JSON.dump(SimpleCov::ResultAdapter.call(project_files)))
        end

        def absorb(coverage)
          @children = SimpleCov::Combine::ResultsCombiner.combine(@children || {}, coverage)
        end

        def store
          return unless @children

          result = SimpleCov::Result.new(@children, command_name: "#{SimpleCov.command_name} (isolated)")
          SimpleCov::ResultMerger.store_result(result)
        end
      end
    end
  end
end

if defined?(SimpleCov) && SimpleCov.running
  Test::Isolation.singleton_class.prepend(Test::Isolation::Coverage)
  at_exit { Test::Isolation::Coverage.store }
end
