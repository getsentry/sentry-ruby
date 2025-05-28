# frozen_string_literal: true

RSpec.describe Sentry::Backtrace do
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

  let(:parsed_backtrace) do
    described_class.parse(backtrace, fixture_root, configuration.app_dirs_pattern)
  end

  describe ".parse" do
    it "returns an array of StacktraceInterface::Frames with correct information" do
      lines = parsed_backtrace.lines.reverse

      expect(lines.count).to eq(2)

      first_line = lines.first

      expect(first_line.file).to match(/stacktrace_test_fixture.rb/)
      expect(first_line.method).to eq("foo")
      expect(first_line.number).to eq(2)

      second_line = lines.last

      expect(second_line.file).to match(/stacktrace_test_fixture.rb/)
      expect(second_line.method).to eq("bar")
      expect(second_line.number).to eq(6)
    end

    context "with Java backtrace" do
      let(:java_backtrace) do
        [
          "org.jruby.runtime.callsite.CachingCallSite.call(CachingCallSite.java:170)",
          "org.jruby.runtime.callsite.CachingCallSite.callBlock(CachingCallSite.java:216)",
          "com.example.package.LongClassName.someMethod(LongClassName.java:55)"
        ]
      end

      let(:parsed_java_backtrace) do
        described_class.parse(java_backtrace, fixture_root, configuration.app_dirs_pattern)
      end

      it "correctly parses Java stack traces" do
        lines = parsed_java_backtrace.lines

        expect(lines.count).to eq(3)

        first_line = lines.first
        expect(first_line.file).to eq("CachingCallSite.java")
        expect(first_line.method).to eq("call")
        expect(first_line.module_name).to eq("org.jruby.runtime.callsite.CachingCallSite")
        expect(first_line.number).to eq(170)

        last_line = lines.last
        expect(last_line.file).to eq("LongClassName.java")
        expect(last_line.method).to eq("someMethod")
        expect(last_line.module_name).to eq("com.example.package.LongClassName")
        expect(last_line.number).to eq(55)
      end
    end
  end

  it "calls backtrace_cleanup_callback if it's present in the configuration" do
    called = false
    callback = proc do |backtrace|
      called = true
      backtrace
    end
    Sentry::Backtrace.parse(Thread.current.backtrace, configuration.project_root, configuration.app_dirs_pattern, &callback)

    expect(called).to eq(true)
  end

  it "#lines" do
    expect(parsed_backtrace.lines.first).to be_a(Sentry::Backtrace::Line)
  end

  it "#inspect" do
    expect(parsed_backtrace.inspect).to match(/Backtrace: .*>$/)
  end

  it "#to_s" do
    expect(parsed_backtrace.to_s).to match(/stacktrace_test_fixture.rb:\d/)
  end

  it "==" do
    backtrace2 = Sentry::Backtrace.new(parsed_backtrace.lines)
    expect(parsed_backtrace).to be == backtrace2
  end
end
