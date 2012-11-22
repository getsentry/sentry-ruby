require File::expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven::Event do
  context 'a fully implemented event' do
    let(:hash) { Raven::Event.new({
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
      }).to_hash()}

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
        Raven::Event.capture_message(message, {:logger => 'logger'}).logger.should == 'logger'
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
        hash['sentry.interfaces.Stacktrace']['frames'][0]['in_app'].should eq(false)
        hash['sentry.interfaces.Stacktrace']['frames'][0]['in_app'].should eq(false)
      end

      context 'in a rails environment' do

        before do
          rails = double('Rails')
          rails.stub(:root) { '/rails/root' }
          stub_const('Rails', rails)
        end

        context 'with an application stacktrace' do
          let(:exception) do
            e = Exception.new(message)
            e.stub(:backtrace).and_return([
              "/rails/root/foobar:132:in `new_function'",
              "/app/some/other/path:1412:in `other_function'",
            ])
            e
          end

          it 'marks in_app correctly' do
            hash['sentry.interfaces.Stacktrace']['frames'][0]['filename'].should eq("/app/some/other/path")
            hash['sentry.interfaces.Stacktrace']['frames'][0]['in_app'].should eq(true)
            hash['sentry.interfaces.Stacktrace']['frames'][1]['filename'].should eq("/rails/root/foobar")
            hash['sentry.interfaces.Stacktrace']['frames'][1]['in_app'].should eq(false)
          end
        end
      end

      it "sets the culprit" do
        hash['culprit'].should eq("/path/to/some/file in function_name")
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
      Raven::Event.capture_exception(exception, {:logger => 'logger'}).logger.should == 'logger'
    end
  end
end
