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
      configuration.current_environment = "test"
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

  context 'rack context specified' do
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
        'REMOTE_ADDR' => '192.168.1.1',
        'PATH_INFO' => '/lol',
        'rack.url_scheme' => 'http',
        'rack.input' => StringIO.new('foo=bar')
      )
    end

    let(:event) do
      Sentry::Event.new(configuration: Sentry.configuration)
    end

    context "without config.send_default_pii = true" do
      it "filters out pii data" do
        Sentry.get_current_scope.apply_to_event(event)

        expect(event.to_hash[:request]).to eq(
          env: { 'SERVER_NAME' => 'localhost', 'SERVER_PORT' => '80' },
          headers: { 'Host' => 'localhost' },
          method: 'POST',
          query_string: 'biz=baz',
          url: 'http://localhost/lol',
          cookies: nil
        )
        expect(event.to_hash[:user][:ip_address]).to eq(nil)
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
          headers: { 'Host' => 'localhost', "X-Forwarded-For" => "1.1.1.1, 2.2.2.2" },
          method: 'POST',
          query_string: 'biz=baz',
          url: 'http://localhost/lol',
          cookies: {}
        )

        expect(event.to_hash[:user][:ip_address]).to eq("1.1.1.1")
      end
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
