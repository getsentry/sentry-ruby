require 'spec_helper'

RSpec.describe Sentry::Event do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = DUMMY_DSN
    end
  end

  describe "#initialize" do
    it "initializes a Event when all required keys are provided" do
      expect(described_class.new(configuration: configuration)).to be_a(described_class)
    end

    it "initializes a Event with correct default values" do
      configuration.server_name = "foo.local"
      configuration.environment = "test"
      configuration.release = "721e41770371db95eee98ca2707686226b993eda"

      event = described_class.new(configuration: configuration)

      expect(event.timestamp).to be_a(String)
      expect(event.user).to eq({})
      expect(event.extra).to eq({})
      expect(event.contexts).to eq({})
      expect(event.tags).to eq({})
      expect(event.fingerprint).to eq([])
      expect(event.platform).to eq(:ruby)
      expect(event.server_name).to eq("foo.local")
      expect(event.environment).to eq("test")
      expect(event.release).to eq("721e41770371db95eee98ca2707686226b993eda")
      expect(event.sdk).to eq("name" => "sentry.ruby", "version" => Sentry::VERSION)
    end
  end

  context 'rack context specified', rack: true do
    require 'stringio'

    before do
      Sentry.init do |config|
        config.dsn = DUMMY_DSN
      end

      Sentry.get_current_scope.set_rack_env(
        'REQUEST_METHOD' => 'POST',
        'QUERY_STRING' => 'biz=baz',
        'HTTP_HOST' => 'localhost',
        'SERVER_NAME' => 'localhost',
        'SERVER_PORT' => '80',
        'HTTP_X_FORWARDED_FOR' => '1.1.1.1, 2.2.2.2',
        'HTTP_X_REQUEST_ID' => 'abcd-1234-abcd-1234',
        'REMOTE_ADDR' => '192.168.1.1',
        'PATH_INFO' => '/lol',
        'rack.url_scheme' => 'http',
        'rack.input' => StringIO.new('foo=bar')
      )
    end

    let(:event) do
      Sentry::Event.new(configuration: Sentry.configuration)
    end

    let(:scope) { Sentry.get_current_scope }

    context "without config.send_default_pii = true" do
      it "filters out pii data" do
        scope.apply_to_event(event)

        expect(event.to_hash[:request]).to eq(
          env: { 'SERVER_NAME' => 'localhost', 'SERVER_PORT' => '80' },
          headers: { 'Host' => 'localhost', 'X-Request-Id' => 'abcd-1234-abcd-1234' },
          method: 'POST',
          query_string: 'biz=baz',
          url: 'http://localhost/lol',
        )
        expect(event.to_hash[:tags][:request_id]).to eq("abcd-1234-abcd-1234")
        expect(event.to_hash[:user][:ip_address]).to eq(nil)
      end

      it "removes ip address headers" do
        scope.apply_to_event(event)

        # doesn't affect scope's rack_env
        expect(scope.rack_env).to include("REMOTE_ADDR")
        expect(event.request.headers.keys).not_to include("REMOTE_ADDR")
        expect(event.request.headers.keys).not_to include("Client-Ip")
        expect(event.request.headers.keys).not_to include("X-Real-Ip")
        expect(event.request.headers.keys).not_to include("X-Forwarded-For")
      end
    end

    context "with config.send_default_pii = true" do
      before do
        Sentry.configuration.send_default_pii = true
      end

      it "adds correct data" do
        Sentry.get_current_scope.apply_to_event(event)

        expect(event.to_hash[:request]).to eq(
          data: { 'foo' => 'bar' },
          env: { 'SERVER_NAME' => 'localhost', 'SERVER_PORT' => '80', "REMOTE_ADDR" => "192.168.1.1" },
          headers: { 'Host' => 'localhost', "X-Forwarded-For" => "1.1.1.1, 2.2.2.2", "X-Request-Id" => "abcd-1234-abcd-1234" },
          method: 'POST',
          query_string: 'biz=baz',
          url: 'http://localhost/lol',
          cookies: {}
        )

        expect(event.to_hash[:tags][:request_id]).to eq("abcd-1234-abcd-1234")
        expect(event.to_hash[:user][:ip_address]).to eq("1.1.1.1")
      end
    end
  end

  describe "#collect_stacktrace_frames" do
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
      described_class.new(configuration: configuration)
    end

    it "returns an array of StacktraceInterface::Frames with correct information" do
      frames = subject.collect_stacktrace_frames(backtrace)

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

  describe '#to_json_compatible' do
    subject do
      Sentry::Event.new(configuration: configuration).tap do |event|
        event.extra = {
          'my_custom_variable' => 'value',
          'date' => Time.utc(0),
          'anonymous_module' => Class.new
        }
      end
    end

    it "should coerce non-JSON-compatible types" do
      json = subject.to_json_compatible

      expect(json["extra"]['my_custom_variable']).to eq('value')
      expect(json["extra"]['date']).to be_a(String)
      expect(json["extra"]['anonymous_module']).not_to be_a(Class)
    end
  end
end
