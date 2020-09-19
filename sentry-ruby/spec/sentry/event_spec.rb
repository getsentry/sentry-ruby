require 'spec_helper'

RSpec.describe Sentry::Event do
  let(:configuration) { Sentry::Configuration.new }
  let(:essential_options) do
    {
      configuration: configuration
    }
  end

  describe "#initialize" do
    it "initializes a Event when all required keys are provided" do
      expect(described_class.new(essential_options)).to be_a(described_class)
    end
  end

  context 'a fully implemented event' do
    let(:hash) do
      Sentry::Event.new(
        configuration: configuration,
        message: 'test',
        level: 'warn',
        tags: {
          'foo' => 'bar'
        },
        extra: {
          'my_custom_variable' => 'value'
        },
        server_name: 'foo.local',
        release: '721e41770371db95eee98ca2707686226b993eda',
        environment: 'production'
      ).to_hash
    end

    it 'has message' do
      expect(hash[:message]).to eq('test')
    end

    it 'has level' do
      expect(hash[:level]).to eq(:warning)
    end

    it 'has server name' do
      expect(hash[:server_name]).to eq('foo.local')
    end

    it 'has release' do
      expect(hash[:release]).to eq('721e41770371db95eee98ca2707686226b993eda')
    end

    it 'has environment' do
      expect(hash[:environment]).to eq('production')
    end

    it 'has tag data' do
      expect(hash[:tags]).to eq('foo' => 'bar')
    end

    it 'has extra data' do
      expect(hash[:extra]["my_custom_variable"]).to eq('value')
    end

    it 'has platform' do
      expect(hash[:platform]).to eq(:ruby)
    end

    it 'has SDK' do
      expect(hash[:sdk]).to eq("name" => "sentry-ruby", "version" => Sentry::VERSION)
    end

    it 'has server os' do
      expect(hash[:extra][:server][:os].keys).to eq([:name, :version, :build, :kernel_version])
    end

    it 'has runtime' do
      expect(hash[:extra][:server][:runtime][:version]).to match(/ruby/)
    end
  end

  context 'parameter entries are nil' do
    let(:hash) do
      Sentry::Event.new(
        message: 'test',
        level: 'warn',
        tags: nil,
        extra: nil,
        user: nil,
        server_name: 'foo.local',
        release: '721e41770371db95eee98ca2707686226b993eda',
        environment: 'production',
        configuration: configuration
      ).to_hash
    end

    it "skips nil values" do
      expect(hash[:extra]).to eq({})
      expect(hash[:user]).to eq({})
      expect(hash[:tags]).to eq({})
    end
  end

  context 'configuration tags specified' do
    let(:hash) do
      config = Sentry::Configuration.new
      config.tags = { 'key' => 'value' }
      config.release = "custom"
      config.current_environment = "custom"

      Sentry::Event.new(
        level: 'warning',
        tags: {
          'foo' => 'bar'
        },
        server_name: 'foo.local',
        configuration: config,
      ).to_hash
    end

    it 'merges tags data' do
      expect(hash[:tags]).to eq('key' => 'value',
                                'foo' => 'bar')
      expect(hash[:release]).to eq("custom")
      expect(hash[:environment]).to eq("custom")
    end

    it 'does not persist tags between unrelated events' do
      config = Sentry::Configuration.new
      config.logger = Logger.new(nil)

      Sentry::Event.new(
        level: 'warning',
        tags: {
          'foo' => 'bar'
        },
        server_name: 'foo.local',
        configuration: config
      )

      hash = Sentry::Event.new(
        level: 'warning',
        server_name: 'foo.local',
        configuration: config
      ).to_hash

      expect(hash[:tags]).to eq({})
    end
  end

  # context 'tags hierarchy respected' do
  #   let(:hash) do
  #     config = Sentry::Configuration.new
  #     config.logger = Logger.new(nil)
  #     config.tags = {
  #       'configuration_context_event_key' => 'configuration_value',
  #       'configuration_context_key' => 'configuration_value',
  #       'configuration_event_key' => 'configuration_value',
  #       'configuration_key' => 'configuration_value'
  #     }

  #     Sentry.tags_context('configuration_context_event_key' => 'context_value',
  #                        'configuration_context_key' => 'context_value',
  #                        'context_event_key' => 'context_value',
  #                        'context_key' => 'context_value')

  #     Sentry::Event.new(
  #       level: 'warning',
  #       logger: 'foo',
  #       tags: {
  #         'configuration_context_event_key' => 'event_value',
  #         'configuration_event_key' => 'event_value',
  #         'context_event_key' => 'event_value',
  #         'event_key' => 'event_value'
  #       },
  #       server_name: 'foo.local',
  #       configuration: config
  #     ).to_hash
  #   end

  #   it 'merges tags data' do
  #     expect(hash[:tags]).to eq('configuration_context_event_key' => 'event_value',
  #                               'configuration_context_key' => 'context_value',
  #                               'configuration_event_key' => 'event_value',
  #                               'context_event_key' => 'event_value',
  #                               'configuration_key' => 'configuration_value',
  #                               'context_key' => 'context_value',
  #                               'event_key' => 'event_value')
  #   end
  # end

  describe '#to_json_compatible' do
    subject do
      Sentry::Event.new(
        extra: {
          'my_custom_variable' => 'value',
          'date' => Time.utc(0),
          'anonymous_module' => Class.new
        },
        configuration: configuration
      )
    end

    it "should coerce non-JSON-compatible types" do
      json = subject.to_json_compatible

      expect(json["extra"]['my_custom_variable']).to eq('value')
      expect(json["extra"]['date']).to be_a(String)
      expect(json["extra"]['anonymous_module']).not_to be_a(Class)
    end

    # context "with bad data" do
    #   subject do
    #     data = {}
    #     data['data'] = data
    #     data['ary'] = []
    #     data['ary'].push('x' => data['ary'])
    #     data['ary2'] = data['ary']

    #     Sentry::Event.new(extra: {
    #                        invalid: "invalid\255".dup.force_encoding('UTF-8'),
    #                        circular: data
    #                      },
    #                      configuration: configuration)
    #   end

    #   it "should remove bad UTF-8" do
    #     json = subject.to_json_compatible

    #     expect(json["extra"]["invalid"]).to eq("invalid")
    #   end

    #   it "should remove circular references" do
    #     json = subject.to_json_compatible

    #     expect(json["extra"]["circular"]["ary2"]).to eq("(...)")
    #   end
    # end
  end
end
