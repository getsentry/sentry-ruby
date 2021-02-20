require 'spec_helper'

RSpec.describe Sentry::StacktraceBuilder do
  describe "#build" do
    let(:fixture_root) { File.join(Dir.pwd, "spec", "support") }
    let(:fixture_file) { File.join(fixture_root, "stacktrace_test_fixture.rb") }
    let(:configuration) do
      Sentry::Configuration.new.tap do |config|
        config.project_root = fixture_root
      end
    end

    let(:backtrace) do
      [
        "#{fixture_file}:6:in `bar'",
        "#{fixture_file}:2:in `foo'"
      ]
    end

    subject do
      configuration.stacktrace_builder
    end

    it "returns an array of StacktraceInterface::Frames with correct information" do
      interface = subject.build(backtrace)
      expect(interface).to be_a(Sentry::StacktraceInterface)

      frames = interface.frames

      first_frame = frames.first

      expect(first_frame.filename).to match(/stacktrace_test_fixture.rb/)
      expect(first_frame.function).to eq("foo")
      expect(first_frame.lineno).to eq(2)
      expect(first_frame.pre_context).to eq([nil, nil, "def foo\n"])
      expect(first_frame.context_line).to eq("  bar\n")
      expect(first_frame.post_context).to eq(["end\n", "\n", "def bar\n"])

      second_frame = frames.last

      expect(second_frame.filename).to match(/stacktrace_test_fixture.rb/)
      expect(second_frame.function).to eq("bar")
      expect(second_frame.lineno).to eq(6)
      expect(second_frame.pre_context).to eq(["end\n", "\n", "def bar\n"])
      expect(second_frame.context_line).to eq("  baz\n")
      expect(second_frame.post_context).to eq(["end\n", nil, nil])
    end
  end
end
