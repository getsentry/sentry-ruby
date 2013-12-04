require File.expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven::Event do
  before do
    Raven::Context.clear!
  end

  context 'a fully implemented event' do
    let(:hash) do
      Raven::Event.new({
        :message => 'test',
        :level => 'warning',
        :logger => 'foo',
        :tags => {
          'foo' => 'bar'
        },
        :extra => {
          'my_custom_variable' => 'value'
        },
        :server_name => 'foo.local',
      }).to_hash
    end

    it 'has message' do
      hash['message'].should == 'test'
    end

    it 'has level' do
      hash['level'].should == 30
    end

    it 'has logger' do
      hash['logger'].should == 'foo'
    end

    it 'has server name' do
      hash['server_name'].should == 'foo.local'
    end

    it 'has tag data' do
      hash['tags'].should == {
        'foo' => 'bar'
      }
    end

    it 'has extra data' do
      hash['extra'].should == {
        'my_custom_variable' => 'value'
      }
    end

    it 'has platform' do
      hash['platform'].should == 'ruby'
    end

  end

  context 'user context specified' do
    let(:hash) do
      Raven.user_context({
        'id' => 'hello',
      })

      Raven::Event.new({
        :level => 'warning',
        :logger => 'foo',
        :tags => {
          'foo' => 'bar'
        },
        :extra => {
          'my_custom_variable' => 'value'
        },
        :server_name => 'foo.local',
      }).to_hash
    end

    it "adds user data" do
      hash['sentry.interfaces.User'].should == {
        'id' => 'hello',
      }
    end
  end

  context 'tags context specified' do
    let(:hash) do
      Raven.tags_context({
        'key' => 'value',
      })

      Raven::Event.new({
        :level => 'warning',
        :logger => 'foo',
        :tags => {
          'foo' => 'bar'
        },
        :extra => {
          'my_custom_variable' => 'value'
        },
        :server_name => 'foo.local',
      }).to_hash
    end

    it "merges tags data" do
      hash['tags'].should == {
        'key' => 'value',
        'foo' => 'bar',
      }
    end
  end

  context 'extra context specified' do
    let(:hash) do
      Raven.extra_context({
        'key' => 'value',
      })

      Raven::Event.new({
        :level => 'warning',
        :logger => 'foo',
        :tags => {
          'foo' => 'bar'
        },
        :extra => {
          'my_custom_variable' => 'value'
        },
        :server_name => 'foo.local',
      }).to_hash
    end

    it "merges extra data" do
      hash['extra'].should == {
        'key' => 'value',
        'my_custom_variable' => 'value',
      }
    end
  end

  context 'rack context specified' do
    require 'stringio'

    let(:hash) do
      Raven.rack_context({
        'REQUEST_METHOD' => 'POST',
        'QUERY_STRING' => 'biz=baz',
        'HTTP_HOST' => 'localhost',
        'SERVER_NAME' => 'localhost',
        'SERVER_PORT' => '80',
        'PATH_INFO' => '/lol',
        'rack.url_scheme' => 'http',
        'rack.input' => StringIO.new('foo=bar'),
      })

      Raven::Event.new({
        :level => 'warning',
        :logger => 'foo',
        :tags => {
          'foo' => 'bar'
        },
        :extra => {
          'my_custom_variable' => 'value'
        },
        :server_name => 'foo.local',
      }).to_hash
    end

    it "adds http data" do
      hash['sentry.interfaces.Http'].should == {
        'data' => { 'foo' => 'bar' },
        'env' => { 'SERVER_NAME' => 'localhost', 'SERVER_PORT' => '80' },
        'headers' => { 'Host' => 'localhost' },
        'method' => 'POST',
        'query_string' => 'biz=baz',
        'url' => 'http://localhost/lol'
      }
    end
  end

  context 'configuration tags specified' do
    let(:hash) do
      config = Raven::Configuration.new
      config.tags = { 'key' => 'value' }

      Raven::Event.new(
        :level => 'warning',
        :logger => 'foo',
        :tags => {
          'foo' => 'bar'
        },
        :server_name => 'foo.local',
        :configuration => config
      ).to_hash
    end

    it 'merges tags data' do
      hash['tags'].should == {
        'key' => 'value',
        'foo' => 'bar'
      }
    end
  end

  describe '.initialize' do
    it 'should not touch the env object for an ignored environment' do
      Raven.configure(true) do |config|
        config.current_environment = 'test'
      end
      Raven.rack_context({})
      expect { Raven::Event.new }.not_to raise_error
    end
  end

  describe '.capture_message' do
    let(:message) { 'This is a message' }
    let(:hash) { Raven::Event.capture_message(message).to_hash }

    context 'for a Message' do
      it 'returns an event' do
        Raven::Event.capture_message(message).should be_a(Raven::Event)
      end

      it "sets the message to the value passed" do
        hash['message'].should == message
      end

      it 'has level ERROR' do
        hash['level'].should == 40
      end

      it 'accepts an options hash' do
        Raven::Event.capture_message(message, :logger => 'logger').logger.should == 'logger'
      end
    end
  end

  describe '.capture_exception' do
    let(:message) { 'This is a message' }
    let(:exception) { Exception.new(message) }
    let(:hash) { Raven::Event.capture_exception(exception).to_hash }

    context 'for an Exception' do
      it 'returns an event' do
        Raven::Event.capture_exception(exception).should be_a(Raven::Event)
      end

      it "sets the message to the exception's message and type" do
        hash['message'].should == "Exception: #{message}"
      end

      # sentry uses python's logging values; 40 is the value of logging.ERROR
      it 'has level ERROR' do
        hash['level'].should == 40
      end

      it 'uses the exception class name as the exception type' do
        hash['sentry.interfaces.Exception']['type'].should == 'Exception'
      end

      it 'uses the exception message as the exception value' do
        hash['sentry.interfaces.Exception']['value'].should == message
      end

      it 'does not belong to a module' do
        hash['sentry.interfaces.Exception']['module'].should == ''
      end
    end

    context 'for a nested exception type' do
      module Raven::Test
        class Exception < Exception; end
      end
      let(:exception) { Raven::Test::Exception.new(message) }

      it 'sends the module name as part of the exception info' do
        hash['sentry.interfaces.Exception']['module'].should == 'Raven::Test'
      end
    end

    context 'for a Raven::Error' do
      let(:exception) { Raven::Error.new }
      it 'does not create an event' do
        Raven::Event.capture_exception(exception).should be_nil
      end
    end

    context 'for an excluded exception type' do
      it 'returns nil for a string match' do
        config = Raven::Configuration.new
        config.excluded_exceptions << 'RuntimeError'
        Raven::Event.capture_exception(RuntimeError.new,
                                       :configuration => config).should be_nil
      end

      it 'returns nil for a class match' do
        module Raven::Test
          class BaseExc < Exception; end
          class SubExc < BaseExc; end
        end

        config = Raven::Configuration.new
        config.excluded_exceptions << Raven::Test::BaseExc

        Raven::Event.capture_exception(Raven::Test::SubExc.new,
                                       :configuration => config).should be_nil
      end
    end

    context 'when the exception has a backtrace' do
      let(:exception) do
        e = Exception.new(message)
        e.stub(:backtrace).and_return([
          "/path/to/some/file:22:in `function_name'",
          "/some/other/path:1412:in `other_function'",
        ])
        e
      end

      it 'parses the backtrace' do
        hash['sentry.interfaces.Stacktrace']['frames'].length.should eq(2)
        hash['sentry.interfaces.Stacktrace']['frames'][0]['lineno'].should eq(1412)
        hash['sentry.interfaces.Stacktrace']['frames'][0]['function'].should eq('other_function')
        hash['sentry.interfaces.Stacktrace']['frames'][0]['filename'].should eq('/some/other/path')

        hash['sentry.interfaces.Stacktrace']['frames'][1]['lineno'].should eq(22)
        hash['sentry.interfaces.Stacktrace']['frames'][1]['function'].should eq('function_name')
        hash['sentry.interfaces.Stacktrace']['frames'][1]['filename'].should eq('/path/to/some/file')
      end

      context 'with internal backtrace' do
        let(:exception) do
          e = Exception.new(message)
          e.stub(:backtrace).and_return(["<internal:prelude>:10:in `synchronize'"])
          e
        end

        it 'marks filename and in_app correctly' do
          hash['sentry.interfaces.Stacktrace']['frames'][0]['lineno'].should eq(10)
          hash['sentry.interfaces.Stacktrace']['frames'][0]['function'].should eq("synchronize")
          hash['sentry.interfaces.Stacktrace']['frames'][0]['filename'].should eq("<internal:prelude>")
        end
      end

      context 'in a rails environment' do

        before do
          rails = double('Rails')
          rails.stub(:root) { '/rails/root' }
          stub_const('Rails', rails)
          Raven.configure(true) do |config|
            config.project_root ||= ::Rails.root
          end
        end

        context 'with an application stacktrace' do
          let(:exception) do
            e = Exception.new(message)
            e.stub(:backtrace).and_return([
              "/rails/root/vendor/bundle/cache/other_gem.rb:10:in `public_method'",
              "vendor/bundle/some_gem.rb:10:in `a_method'",
              "/rails/root/app/foobar:132:in `new_function'",
              "/gem/lib/path:87:in `a_function'",
              "/app/some/other/path:1412:in `other_function'",
              "test/some/other/path:1412:in `other_function'"
            ])
            e
          end

          it 'marks in_app correctly' do
            Raven.configuration.project_root.should eq('/rails/root')
            hash['sentry.interfaces.Stacktrace']['frames'][0]['filename'].should eq("test/some/other/path")
            hash['sentry.interfaces.Stacktrace']['frames'][0]['in_app'].should eq(true)
            hash['sentry.interfaces.Stacktrace']['frames'][1]['filename'].should eq("/app/some/other/path")
            hash['sentry.interfaces.Stacktrace']['frames'][1]['in_app'].should eq(false)
            hash['sentry.interfaces.Stacktrace']['frames'][2]['filename'].should eq("/gem/lib/path")
            hash['sentry.interfaces.Stacktrace']['frames'][2]['in_app'].should eq(false)
            hash['sentry.interfaces.Stacktrace']['frames'][3]['filename'].should eq("/rails/root/app/foobar")
            hash['sentry.interfaces.Stacktrace']['frames'][3]['in_app'].should eq(true)
            hash['sentry.interfaces.Stacktrace']['frames'][4]['filename'].should eq("vendor/bundle/some_gem.rb")
            hash['sentry.interfaces.Stacktrace']['frames'][4]['in_app'].should eq(false)
            hash['sentry.interfaces.Stacktrace']['frames'][5]['filename'].should eq("/rails/root/vendor/bundle/cache/other_gem.rb")
            hash['sentry.interfaces.Stacktrace']['frames'][5]['in_app'].should eq(false)
          end
        end
      end

      it "sets the culprit" do
        hash['culprit'].should eq("/path/to/some/file in function_name at line 22")
      end

      context 'when a path in the stack trace is on the laod path' do
        before do
          $LOAD_PATH << '/some'
        end

        after do
          $LOAD_PATH.delete('/some')
        end

        it 'strips prefixes in the load path from frame filenames' do
          hash['sentry.interfaces.Stacktrace']['frames'][0]['filename'].should eq('other/path')
        end
      end
    end

    it 'accepts an options hash' do
      Raven::Event.capture_exception(exception, :logger => 'logger').logger.should == 'logger'
    end

    it 'uses an annotation if one exists' do
      Raven.annotate_exception(exception, :logger => 'logger')
      expect(Raven::Event.capture_exception(exception).logger).to eq('logger')
    end
  end
end
