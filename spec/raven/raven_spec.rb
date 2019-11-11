require 'spec_helper'

RSpec.describe Raven do
  let(:event) { Raven::Event.new(:id => "event_id") }
  let(:options) { double("options") }

  before do
    allow(Raven.instance).to receive(:send_event)
    allow(Raven::Event).to receive(:from_message) { event }
    allow(Raven::Event).to receive(:from_exception) { event }
  end

  describe '.capture' do
    context 'not given a block' do
      let(:options) { { :key => 'value' } }

      def capture_in_separate_process
        pipe_in, pipe_out = IO.pipe

        fork do
          pipe_in.close
          described_class.capture(options)

          allow(Raven.instance).to receive(:capture_type) do |exception, _options|
            pipe_out.puts exception.message
          end

          # silence process
          $stderr.reopen('/dev/null', 'w')
          $stdout.reopen('/dev/null', 'w')

          yield
          exit
        end

        pipe_out.close
        captured_messages = pipe_in.read
        pipe_in.close
        # sometimes the at_exit hook was registered multiple times
        captured_messages.split("\n").last
      end

      it 'does not yield' do
        # As there is no yield matcher that does not require a probe (e.g. this
        # is not valid: expect { |b| described_class.capture }.to_not yield_control),
        # expect that a LocalJumpError, which is raised when yielding when no
        # block is defined, is not raised.
        described_class.capture
      end

      it 'installs an at exit hook that will capture exceptions' do
        skip('fork not supported in jruby') if RUBY_PLATFORM == 'java'
        captured_message = capture_in_separate_process { raise 'test error' }
        expect(captured_message).to eq('test error')
      end
    end
  end

  describe '.inject_only' do
    before do
      allow(Gem.loaded_specs).to receive(:keys).and_return(%w(railties rack sidekiq))
    end

    it 'loads integrations when they are valid configurations' do
      expect(Raven).to receive(:load_integration).once.with('railties')
      expect(Raven).to receive(:load_integration).once.with('sidekiq')

      Raven.inject_only(:railties, :sidekiq)
    end

    it 'skips any integrations that are not supported' do
      expect(Raven).to receive(:load_integration).once.with('railties')
      expect(Raven.logger).to receive(:warn).with('Integrations do not exist: doesnot, exist')

      Raven.inject_only(:railties, :doesnot, :exist)
    end

    it 'skips any integrations that are not loaded in the gemspec' do
      expect(Raven).to receive(:load_integration).once.with('railties')

      Raven.inject_only(:railties, :delayed_job)
    end
  end

  describe '.inject_without' do
    before do
      allow(Gem.loaded_specs).to receive(:keys).and_return(Raven::AVAILABLE_INTEGRATIONS)
    end

    it 'injects all integrations except those passed as an argument' do
      expect(Raven).to receive(:load_integration).once.with('rake')

      Raven.inject_without(:delayed_job, :logger, :railties, :sidekiq, :rack, :"rack-timeout")
    end
  end

  describe "#sys_command" do
    it "should execute system commands" do
      expect(Raven.sys_command("echo 'Sentry'")).to eq("Sentry")
    end

    it "should return nil if a system command doesn't exist" do
      expect(Raven.sys_command("asdasdasdsa")).to eq(nil)
    end

    it "should return nil if the process exits with a non-zero exit status" do
      expect(Raven.sys_command("uname -c")).to eq(nil) # non-existent uname option
    end

    it "should not output to stdout on failure" do
      expect { Raven.sys_command("asdasdasdsa") }.to_not output.to_stdout
      expect { Raven.sys_command("uname -c") }.to_not output.to_stdout
    end

    it "should tolerate a missing $CHILD_STATUS" do
      Signal.trap('CLD', 'DEFAULT')
      expect(Raven.sys_command("echo 'Sentry'")).to eq("Sentry")
    end
  end
end
