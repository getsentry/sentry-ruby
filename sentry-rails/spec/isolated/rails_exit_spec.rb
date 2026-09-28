# frozen_string_literal: true

RSpec.describe Sentry::Rails, type: :request do
  context "at exit" do
    before do
      make_basic_app
      Rails.application.load_runner
    end

    it "captures exception if exit code is non-zero" do
      skip('fork not supported in jruby') if RUBY_PLATFORM == 'java'
      captured_message = capture_in_separate_process(exit_code: 1) do |pipe_out|
        allow(Sentry::Rails).to receive(:capture_exception) do |event|
          pipe_out.puts event
        end

        # silence process
        $stderr.reopen('/dev/null', 'w')
        $stdout.reopen('/dev/null', 'w')
      end
      captured_message = captured_message.split("\n").last

      expect(captured_message).to eq('exit')
    end

    it "does not capture exception if exit code is zero" do
      skip('fork not supported in jruby') if RUBY_PLATFORM == 'java'
      captured_message = capture_in_separate_process(exit_code: 0) do |pipe_out|
        allow(Sentry::Rails).to receive(:capture_exception) do |event|
          pipe_out.puts event
        end

        # silence process
        $stderr.reopen('/dev/null', 'w')
        $stdout.reopen('/dev/null', 'w')
      end
      captured_message = captured_message.split("\n").last

      expect(captured_message).to be_nil
    end
  end
end
