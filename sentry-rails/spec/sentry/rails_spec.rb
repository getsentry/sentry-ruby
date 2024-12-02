# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:event) do
    transport.events.last.to_json_compatible
  end

  context "with simplist config" do
    before do
      make_basic_app
    end

    it "has version set" do
      expect(described_class::VERSION).to be_a(String)
    end

    it "inserts middleware to a correct position" do
      app = Rails.application
      index_of_executor = app.middleware.find_index { |m| m == ActionDispatch::ShowExceptions }
      expect(app.middleware.find_index(Sentry::Rails::CaptureExceptions)).to eq(index_of_executor + 1)
      index_of_debug_exceptions = app.middleware.find_index { |m| m == ActionDispatch::DebugExceptions }
      expect(app.middleware.find_index(Sentry::Rails::RescuedExceptionInterceptor)).to eq(index_of_debug_exceptions + 1)
    end

    it "propagates timezone to cron config" do
      # cron.default_timezone is set to nil by default
      expect(Sentry.configuration.cron.default_timezone).to eq("Etc/UTC")
    end

    it "inserts a callback to disable background_worker for the runner mode" do
      Sentry.configuration.background_worker_threads = 10

      Rails.application.load_runner

      expect(Sentry.configuration.background_worker_threads).to eq(0)
    end

    describe "logger detection" do
      it "sets a duplicated Rails logger as the SDK's logger" do
        if Gem::Version.new(Rails.version) > Gem::Version.new("7.1.0.beta")
          expect(Sentry.configuration.logger).to be_a(ActiveSupport::BroadcastLogger)

          Sentry.configuration.logger.level = ::Logger::WARN

          # Configuring the SDK's logger should not affect the Rails logger
          expect(Rails.logger.broadcasts.first).to be_a(ActiveSupport::Logger)
          expect(Rails.logger.broadcasts.first.level).to eq(::Logger::DEBUG)
          expect(Sentry.configuration.logger.level).to eq(::Logger::WARN)
        else
          expect(Sentry.configuration.logger).to be_a(ActiveSupport::Logger)

          Sentry.configuration.logger.level = ::Logger::WARN

          # Configuring the SDK's logger should not affect the Rails logger
          expect(Rails.logger.level).to eq(::Logger::DEBUG)
          expect(Sentry.configuration.logger.level).to eq(::Logger::WARN)
        end
      end

      it "respects the logger set by user" do
        logger = ::Logger.new(nil)

        make_basic_app do |config|
          config.logger = logger
        end

        expect(Sentry.configuration.logger).to eq(logger)
      end

      it "doesn't cause error if Rails::Logger is not present during SDK initialization" do
        Rails.logger = nil

        Sentry.init

        expect(Sentry.configuration.logger).to be_a(Sentry::Logger)
      end
    end

    it "sets Sentry.configuration.project_root correctly" do
      expect(Sentry.configuration.project_root).to eq(Rails.root.to_s)
    end

    it "doesn't clobber a manually configured release" do
      expect(Sentry.configuration.release).to eq('beta')
    end

    it "sets transaction to ControllerName#method and sets correct source" do
      get "/exception"

      expect(transport.events.last.transaction).to eq("HelloController#exception")
      expect(transport.events.last.transaction_info).to eq({ source: :view })

      get "/posts"

      expect(transport.events.last.transaction).to eq("PostsController#index")
      expect(transport.events.last.transaction_info).to eq({ source: :view })
    end

    it "sets correct request url" do
      get "/exception"

      expect(event.dig("request", "url")).to eq("http://www.example.com/exception")
    end

    it "sets the error event id to env" do
      get "/exception"

      expect(response.request.env["sentry.error_event_id"]).to eq(event["event_id"])
    end
  end

  context "at exit" do
    before do
      make_basic_app
      Rails.application.load_runner
    end

    def capture_in_separate_process(exit_code:)
      pipe_in, pipe_out = IO.pipe

      fork do
        pipe_in.close

        allow(Sentry::Rails).to receive(:capture_exception) do |event|
          pipe_out.puts event
        end

        # silence process
        $stderr.reopen('/dev/null', 'w')
        $stdout.reopen('/dev/null', 'w')

        exit exit_code
      end

      pipe_out.close
      captured_messages = pipe_in.read
      pipe_in.close
      # sometimes the at_exit hook was registered multiple times
      captured_messages.split("\n").last
    end

    it "captures exception if exit code is non-zero" do
      skip('fork not supported in jruby') if RUBY_PLATFORM == 'java'
      captured_message = capture_in_separate_process(exit_code: 1)

      expect(captured_message).to eq('exit')
    end

    it "does not capture exception if exit code is zero" do
      skip('fork not supported in jruby') if RUBY_PLATFORM == 'java'
      captured_message = capture_in_separate_process(exit_code: 0)

      expect(captured_message).to be_nil
    end
  end

  RSpec.shared_examples "report_rescued_exceptions" do
    context "with report_rescued_exceptions = true" do
      before do
        Sentry.configuration.rails.report_rescued_exceptions = true
      end

      it "captures exceptions" do
        get "/exception"

        expect(response.status).to eq(500)

        expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
        expect(event["exception"]["values"][0]["value"]).to match("An unhandled exception!")
      end
    end

    context "with report_rescued_exceptions = false" do
      before do
        Sentry.configuration.rails.report_rescued_exceptions = false
      end

      it "doesn't report rescued exceptions" do
        get "/exception"

        expect(transport.events.count).to eq(0)
      end
    end
  end

  context "with development config" do
    before do
      make_basic_app do |config, app|
        app.config.consider_all_requests_local = true
      end
    end

    include_examples "report_rescued_exceptions"
  end

  context "with production config" do
    before do
      make_basic_app do |config, app|
        app.config.consider_all_requests_local = false
      end
    end

    include_examples "report_rescued_exceptions"

    it "doesn't do anything on a normal route" do
      get "/"

      expect(response.status).to eq(200)
      expect(transport.events.size).to eq(0)
    end

    it "excludes commonly seen exceptions (like RecordNotFound)" do
      get "/not_found"

      expect(response.status).to eq(400)
      expect(transport.events).to be_empty
    end

    it "captures exceptions" do
      get "/exception"

      expect(response.status).to eq(500)

      expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
      expect(event["exception"]["values"][0]["value"]).to match("An unhandled exception!")
      expect(event["sdk"]).to eq("name" => "sentry.ruby.rails", "version" => Sentry::Rails::VERSION)
    end

    it "filters exception backtrace with custom BacktraceCleaner" do
      get "/view_exception"

      traces = event.dig("exception", "values", 0, "stacktrace", "frames")
      expect(traces.dig(-1, "filename")).to eq("inline template")

      # we want to avoid something like "_inline_template__3014794444104730113_10960"
      expect(traces.dig(-1, "function")).to be_nil
    end

    it "makes sure BacktraceCleaner gem cleanup doesn't affect context lines population" do
      get "/view_exception"

      traces = event.dig("exception", "values", 0, "stacktrace", "frames")
      gem_frame = traces.find { |t| t["abs_path"].match(/actionview/) }
      expect(gem_frame["pre_context"]).not_to be_empty
      expect(gem_frame["post_context"]).not_to be_empty
      expect(gem_frame["context_line"]).not_to be_empty
    end

    it "doesn't filters exception backtrace if backtrace_cleanup_callback is overridden" do
      make_basic_app do |config|
        config.backtrace_cleanup_callback = lambda { |backtrace| backtrace }
      end

      get "/view_exception"

      traces = event.dig("exception", "values", 0, "stacktrace", "frames")
      expect(traces.dig(-1, "filename")).to eq("inline template")
      expect(traces.dig(-1, "function")).not_to be_nil
    end

    context "with config.exceptions_app = self.routes" do
      before do
        make_basic_app do |config, app|
          app.config.exceptions_app = app.routes
        end
      end

      it "sets transaction to ControllerName#method" do
        get "/exception"

        expect(transport.events.count).to eq(1)
        last_event = transport.events.last
        expect(last_event.transaction).to eq("HelloController#exception")
        expect(transport.events.last.transaction_info).to eq({ source: :view })
        expect(response.body).to match(last_event.event_id)

        get "/posts"

        expect(transport.events.last.transaction).to eq("PostsController#index")
        expect(transport.events.last.transaction_info).to eq({ source: :view })
      end

      it "sets correct request url" do
        get "/exception"

        expect(event.dig("request", "url")).to eq("http://www.example.com/exception")
      end
    end
  end

  context "with trusted proxies set" do
    before do
      make_basic_app do |config, app|
        app.config.action_dispatch.trusted_proxies = ["5.5.5.5"]
      end
    end

    it "sets Sentry.configuration.trusted_proxies correctly" do
      expect(Sentry.configuration.trusted_proxies).to eq(["5.5.5.5"])
    end
  end

  describe "error reporter integration", skip: Rails.version.to_f < 7.0 do
    context "when config.register_error_subscriber = false (default)" do
      before do
        make_basic_app
      end

      it "doesn't register Sentry::Rails::ErrorSubscriber" do
        Rails.error.report(Exception.new, handled: false)

        expect(transport.events.count).to eq(0)

        ActiveSupport.error_reporter.report(Exception.new, handled: false)

        expect(transport.events.count).to eq(0)
      end
    end

    context "when config.register_error_subscriber = true" do
      before do
        make_basic_app do |config|
          config.rails.register_error_subscriber = true
        end
      end

      it "registers Sentry::Rails::ErrorSubscriber to Rails" do
        Rails.error.report(Exception.new, handled: false)

        expect(transport.events.count).to eq(1)

        ActiveSupport.error_reporter.report(Exception.new, handled: false)

        expect(transport.events.count).to eq(2)
      end

      it "sets correct contextual data to the reported event" do
        Rails.error.handle(severity: :info, context: { foo: "bar" }) do
          1/0
        end

        expect(transport.events.count).to eq(1)

        event = transport.events.first

        if Rails.version.to_f > 7.0
          expect(event.tags).to eq({ handled: true, source: "application" })
        else
          expect(event.tags).to eq({ handled: true })
        end

        expect(event.level).to eq(:info)
        expect(event.contexts).to include({ "rails.error" => { foo: "bar" } })
      end

      it "skips cache storage sources", skip: Rails.version.to_f < 7.1 do
        Rails.error.handle(severity: :info, source: "mem_cache_store.active_support") do
          1/0
        end

        expect(transport.events.count).to eq(0)
      end

      it "captures string messages through error reporter" do
        Rails.error.report("Test message", severity: :info, handled: true, context: { foo: "bar" })

        expect(transport.events.count).to eq(1)
        event = transport.events.first

        expect(event.message).to eq("Test message")
        expect(event.level).to eq(:info)
        expect(event.contexts).to include({ "rails.error" => { foo: "bar" } })
        expect(event.tags).to include({ handled: true })
      end

      it "skips non-string and non-exception errors" do
        expect {
          Sentry.init do |config|
            config.logger = Logger.new($stdout)
          end

          Sentry.logger.debug("Expected an Exception or a String, got: #{312.inspect}")

          Rails.error.report(312, severity: :info, handled: true, context: { foo: "bar" })
        }.to output(/Expected an Exception or a String, got: 312/).to_stdout

        expect(transport.events.count).to eq(0)
      end
    end
  end
end
