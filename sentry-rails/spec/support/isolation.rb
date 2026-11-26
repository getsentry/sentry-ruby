# frozen_string_literal: true

module Test
  module Isolation
    TIMEOUT = 120

    ChildCrashed = Class.new(StandardError)

    class Recorder
      attr_reader :examples, :errors

      def initialize
        @examples = {}
        @errors = []
      end

      def example_finished(example)
        result = example.execution_result
        summary = { status: result.status, message: result.pending_message }
        summary[:error] = Isolation.pack(example.exception) if example.exception
        @examples[example.id] = summary
      end

      def notify_non_example_exception(error, context)
        @errors << { error: Isolation.pack(error), context: context }
      end

      def fail_fast_limit_met?
        false
      end

      def example_group_started(_group); end
      def example_group_finished(_group); end
      def example_started(_example); end
      def example_passed(_example); end
      def example_failed(_example); end
      def example_pending(_example); end
    end

    module GroupExtension
      def run(reporter = RSpec::Core::NullReporter)
        return super unless Isolation.isolated_root?(self)
        return if RSpec.world.wants_to_quit

        Isolation.run_group(self, reporter) { |recorder| super(recorder) }
      end
    end

    class << self
      def isolated_root?(group)
        return false unless Process.respond_to?(:fork) && group.metadata[:isolate]

        parent = group.superclass
        !(parent.respond_to?(:metadata) && parent.metadata&.dig(:isolate))
      end

      def run_group(group, reporter, &run)
        examples = group.metadata[:isolate] == :group ? [nil] : ordered_examples(group)

        reporter.example_group_started(group)
        results = examples.map do |only|
          next if RSpec.world.wants_to_quit

          result = run_in_child do
            restrict_to(group, only) if only
            recorder = Recorder.new
            route_hook_errors_to(recorder)
            run.call(recorder)
            { examples: recorder.examples, errors: recorder.errors }
          end
          succeeded = replay(group, only, result, reporter)
          RSpec.world.wants_to_quit = true if !succeeded && reporter.fail_fast_limit_met?
          succeeded
        end
        results.all?
      ensure
        reporter.example_group_finished(group)
      end

      def pack(error)
        dump =
          begin
            Marshal.dump(error)
          rescue TypeError
            nil
          end
        { dump: dump, class: error.class.name, message: error.message, backtrace: error.backtrace }
      end

      def unpack(packed)
        Marshal.load(packed[:dump])
      rescue TypeError, ArgumentError, NameError
        ChildCrashed.new("#{packed[:class]}: #{packed[:message]}").tap { |e| e.set_backtrace(packed[:backtrace] || []) }
      end

      private

      def ordered_examples(group)
        group.ordering_strategy.order(group.filtered_examples) +
          group.ordering_strategy.order(group.children).flat_map { |child| ordered_examples(child) }
      end

      def route_hook_errors_to(recorder)
        RSpec.configuration.reporter.define_singleton_method(:notify_non_example_exception) do |error, context|
          recorder.notify_non_example_exception(error, context)
        end
      end

      def restrict_to(group, example)
        group.descendants.each do |g|
          RSpec.world.filtered_examples[g] = g.filtered_examples.select { |e| e.equal?(example) }
          g.reset_memoized
        end
      end

      def replay(group, only, result, reporter)
        expected = only ? [only] : group.descendant_filtered_examples
        recorded = result[:examples] || {}

        expected.each do |example|
          summary = recorded[example.id] || (result[:crash] && { status: :failed, error: result[:crash] })
          replay_example(example, summary, reporter) if summary
        end

        (result[:errors] || []).each do |entry|
          reporter.notify_non_example_exception(unpack(entry[:error]), entry[:context])
        end

        !result[:crash] && recorded.values.none? { |s| s[:status] == :failed }
      end

      def replay_example(example, summary, reporter)
        RSpec.current_example = example

        case summary[:status]
        when :failed
          example.fail_with_exception(reporter, unpack(summary[:error]))
        when :pending
          example.skip_with_exception(reporter, RSpec::Core::Pending::SkipDeclaredInExample.new(summary[:message]))
        else
          example.send(:start, reporter)
          example.send(:finish, reporter)
        end
      ensure
        example.execution_result.ensure_timing_set(RSpec::Core::Time)
        RSpec.current_example = nil
      end

      def run_in_child
        reader, writer = IO.pipe
        reader.binmode
        writer.binmode

        pid = fork do
          reader.close
          writer.write(Marshal.dump(in_child { yield }))
          writer.close
          $stdout.flush
          $stderr.flush
          exit!(0)
        end

        writer.close
        wait_for_result(reader, pid)
      ensure
        reader&.close
        writer&.close
      end

      def wait_for_result(reader, pid)
        if IO.select([reader], nil, nil, TIMEOUT)
          data = reader.read
          status = Process.wait2(pid).last
          return from_child(Marshal.load(data)) unless data.empty?

          crashed("isolated spec exited without reporting (#{status.inspect})")
        else
          Process.kill("KILL", pid)
          Process.wait(pid)
          crashed("isolated spec timed out after #{TIMEOUT}s")
        end
      end

      def in_child
        yield
      end

      def from_child(payload)
        payload
      end

      def crashed(message)
        { crash: pack(ChildCrashed.new(message).tap { |e| e.set_backtrace([]) }) }
      end
    end
  end
end

RSpec::Core::ExampleGroup.singleton_class.prepend(Test::Isolation::GroupExtension)
