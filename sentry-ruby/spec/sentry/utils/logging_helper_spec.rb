# frozen_string_literal: true

RSpec.describe Sentry::LoggingHelper do
  let(:string_io) { StringIO.new }
  let(:logger) { Logger.new(string_io) }

  let(:helper_class) do
    Class.new do
      include Sentry::LoggingHelper
      attr_accessor :sdk_logger

      def initialize(sdk_logger)
        @sdk_logger = sdk_logger
      end
    end
  end

  let(:logger_helper) { helper_class.new(logger) }

  describe "#log_error" do
    it "logs exception message with description" do
      exception = StandardError.new("Something went wrong")
      logger_helper.log_error("test_error", exception)

      expect(string_io.string).to include("test_error: Something went wrong")
    end

    it "includes backtrace when debug is true" do
      exception = StandardError.new("Error")
      exception.set_backtrace(["it_broke.rb:1"])

      logger_helper.log_error("test_error", exception, debug: true)

      expect(string_io.string).to include("it_broke.rb:1")
    end
  end

  describe "stderr fallback when logger fails" do
    shared_examples "falls back to stderr" do |method_name, *args|
      it "outputs to stderr with error class and message" do
        broken_logger = Class.new do
          def error(*); raise IOError, "oops"; end
          def debug(*); raise IOError, "oops"; end
          def warn(*); raise IOError, "oops"; end
        end.new

        helper = helper_class.new(broken_logger)

        expect($stderr).to receive(:puts).with(/Sentry SDK logging failed \(IOError:/)
        expect { helper.public_send(method_name, *args) }.not_to raise_error
      end
    end

    context "#log_error" do
      include_examples "falls back to stderr", :log_error, "Test", StandardError.new("Error")
    end

    context "#log_debug" do
      include_examples "falls back to stderr", :log_debug, "Debug message"
    end

    context "#log_warn" do
      include_examples "falls back to stderr", :log_warn, "Warning message"
    end
  end

  describe "custom JSON logger with encoding errors" do
    # Custom logger from GitHub issue #2805
    let(:json_logger) do
      Class.new(::Logger) do
        class JsonFormatter
          def call(level, _, _, m)
            { severity: level, message: m }.to_json << "\n"
          end
        end

        def initialize(*)
          super
          self.formatter = JsonFormatter.new
        end
      end.new(StringIO.new)
    end

    let(:logger_helper) { helper_class.new(json_logger) }

    it "scrubs invalid UTF-8 in stderr output when JSON logger fails on encoding" do
      helper = helper_class.new(json_logger)

      invalid_message = "a\x92b"
      exception = StandardError.new("oops")

      stderr_message = nil
      expect($stderr).to receive(:puts) { |msg| stderr_message = msg }

      expect { helper.log_error(invalid_message, exception) }.not_to raise_error

      expect(stderr_message).to include("JSON::GeneratorError")
      expect(stderr_message).to include("a<?>b")
      expect(stderr_message).to include("oops")
    end
  end
end
