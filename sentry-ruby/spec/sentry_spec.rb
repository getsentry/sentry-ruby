RSpec.describe Sentry do
  before do
    perform_basic_setup
  end

  let(:event) do
    Sentry::Event.new(configuration: Sentry::Configuration.new)
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  describe ".init" do
    context "with block argument" do
      it "initializes the current hub and main hub" do
        described_class.init do |config|
          config.dsn = DUMMY_DSN
        end

        current_hub = described_class.get_current_hub
        expect(current_hub).to be_a(Sentry::Hub)
        expect(current_hub.current_scope).to be_a(Sentry::Scope)
        expect(subject.get_main_hub).to eq(current_hub)
      end
    end

    context "without block argument" do
      it "initializes the current hub and main hub" do
        ENV['SENTRY_DSN'] = DUMMY_DSN

        described_class.init

        current_hub = described_class.get_current_hub
        expect(current_hub).to be_a(Sentry::Hub)
        expect(current_hub.current_scope).to be_a(Sentry::Scope)
        expect(subject.get_main_hub).to eq(current_hub)
      end
    end

    it "initializes Scope with correct max_breadcrumbs" do
      described_class.init do |config|
        config.max_breadcrumbs = 1
      end

      current_scope = described_class.get_current_scope
      expect(current_scope.breadcrumbs.buffer.size).to eq(1)
    end
  end

  describe "#clone_hub_to_current_thread" do
    it "clones a new hub to the current thread" do
      main_hub = described_class.get_main_hub

      new_thread = Thread.new do
        described_class.clone_hub_to_current_thread
        thread_hub = described_class.get_current_hub

        expect(thread_hub).to be_a(Sentry::Hub)
        expect(thread_hub).not_to eq(main_hub)
        expect(thread_hub.current_client).to eq(main_hub.current_client)
        expect(described_class.get_main_hub).to eq(main_hub)
      end

      new_thread.join
    end

    it "stores the hub in a thread variable (instead of just fiber variable)" do
      Sentry.set_tags(outside_fiber: true)

      fiber = Fiber.new do
        Sentry.set_tags(inside_fiber: true)
      end

      fiber.resume

      expect(Sentry.get_current_scope.tags).to eq({ outside_fiber: true, inside_fiber: true })
    end
  end

  describe ".configure_scope" do
    it "yields the current hub's scope" do
      scope = nil
      described_class.configure_scope { |s| scope = s }

      expect(scope).to eq(described_class.get_current_hub.current_scope)
    end
  end

  shared_examples "capture_helper" do
    context "without any Sentry setup" do
      before do
        allow(Sentry).to receive(:get_main_hub)
        allow(Sentry).to receive(:get_current_hub)
      end

      it "doesn't cause any issue" do
        described_class.send(capture_helper, capture_subject)
      end
    end

    context "with sending_allowed? condition" do
      before do
        expect(Sentry.configuration).to receive(:sending_allowed?).and_return(false)
      end

      it "doesn't send the event nor assign last_event_id" do
        described_class.send(capture_helper, capture_subject)

        expect(transport.events).to be_empty
        expect(subject.last_event_id).to eq(nil)
      end
    end

    context "when rate limited" do
      let(:string_io) { StringIO.new }
      before do
        perform_basic_setup do |config|
          config.logger = Logger.new(string_io)
          config.transport.transport_class = Sentry::HTTPTransport
        end

        Sentry.get_current_client.transport.rate_limits.merge!("error" => Time.now + 100)
      end

      it "stops the event and logs correct message" do
        described_class.send(capture_helper, capture_subject)

        expect(string_io.string).to match(/Envelope \[event\] not sent: rate limiting/)
      end
    end
  end

  describe ".send_event" do
    let(:event) { Sentry.get_current_client.event_from_message("test message") }

    before do
      Sentry.configuration.before_send = lambda do |event, hint|
        event.tags[:hint] = hint
        event
      end
    end

    it "sends the event" do
      described_class.send_event(event)

      expect(transport.events.count).to eq(1)
    end

    it "sends the event with hint" do
      described_class.send_event(event, { foo: "bar" })

      expect(transport.events.count).to eq(1)
      event = transport.events.last
      expect(event.tags[:hint][:foo]).to eq("bar")
    end
  end

  describe ".capture_event" do
    it_behaves_like "capture_helper" do
      let(:capture_helper) { :capture_event }
      let(:capture_subject) { event }
    end

    it "sends the event via current hub" do
      expect do
        described_class.capture_event(event)
      end.to change { transport.events.count }.by(1)
    end
  end

  describe ".capture_exception" do
    let(:exception) { ZeroDivisionError.new("divided by 0") }

    it_behaves_like "capture_helper" do
      let(:capture_helper) { :capture_exception }
      let(:capture_subject) { exception }
    end

    it "sends the exception via current hub" do
      expect do
        described_class.capture_exception(exception, tags: { foo: "baz" })
      end.to change { transport.events.count }.by(1)
    end

    it "doesn't do anything if the exception is excluded" do
      Sentry.get_current_client.configuration.excluded_exceptions = ["ZeroDivisionError"]

      result = described_class.capture_exception(exception)

      expect(result).to eq(nil)
    end
  end

  describe ".capture_message" do
    let(:message) { "Test" }

    it_behaves_like "capture_helper" do
      let(:capture_helper) { :capture_message }
      let(:capture_subject) { message }
    end

    it "sends the message via current hub" do
      expect do
        described_class.capture_message("Test", tags: { foo: "baz" })
      end.to change { transport.events.count }.by(1)
    end
  end

  describe ".start_transaction" do
    describe "sampler example" do
      before do
        perform_basic_setup do |config|
          config.traces_sampler = lambda do |sampling_context|
            # if this is the continuation of a trace, just use that decision (rate controlled by the caller)
            unless sampling_context[:parent_sampled].nil?
              next sampling_context[:parent_sampled]
            end

            # transaction_context is the transaction object in hash form
            # keep in mind that sampling happens right after the transaction is initialized
            # e.g. at the beginning of the request
            transaction_context = sampling_context[:transaction_context]

            # transaction_context helps you sample transactions with more sophistication
            # for example, you can provide different sample rates based on the operation or name
            op = transaction_context[:op]
            transaction_name = transaction_context[:name]

            case op
            when /request/
              case transaction_name
              when /health_check/
                0.0
              when /payment/
                0.5
              when /api/
                0.2
              else
                0.1
              end
            when /sidekiq/
              0.01 # you may want to set a lower rate for background jobs if the number is large
            else
              0.0 # ignore all other transactions
            end
          end
        end
      end

      it "prioritizes parent's sampling decision" do
        sampled_trace = "d298e6b033f84659928a2267c3879aaa-2a35b8e9a1b974f4-1"
        unsampled_trace = "d298e6b033f84659928a2267c3879aaa-2a35b8e9a1b974f4-0"
        not_sampled_trace = "d298e6b033f84659928a2267c3879aaa-2a35b8e9a1b974f4-"

        transaction = Sentry::Transaction.from_sentry_trace(sampled_trace, op: "rack.request", name: "/payment")
        described_class.start_transaction(transaction: transaction)

        expect(transaction.sampled).to eq(true)

        transaction = Sentry::Transaction.from_sentry_trace(unsampled_trace, op: "rack.request", name: "/payment")
        described_class.start_transaction(transaction: transaction)

        expect(transaction.sampled).to eq(false)

        allow(Random).to receive(:rand).and_return(0.4)
        transaction = Sentry::Transaction.from_sentry_trace(not_sampled_trace, op: "rack.request", name: "/payment")
        described_class.start_transaction(transaction: transaction)

        expect(transaction.sampled).to eq(true)
      end

      it "skips /health_check" do
        transaction = described_class.start_transaction(op: "rack.request", name: "/health_check")
        expect(transaction.sampled).to eq(false)
      end

      it "gives /payment 0.5 of rate" do
        allow(Random).to receive(:rand).and_return(0.4)
        transaction = described_class.start_transaction(op: "rack.request", name: "/payment")
        expect(transaction.sampled).to eq(true)

        allow(Random).to receive(:rand).and_return(0.6)
        transaction = described_class.start_transaction(op: "rack.request", name: "/payment")
        expect(transaction.sampled).to eq(false)
      end

      it "gives /api 0.2 of rate" do
        allow(Random).to receive(:rand).and_return(0.1)
        transaction = described_class.start_transaction(op: "rack.request", name: "/api")
        expect(transaction.sampled).to eq(true)

        allow(Random).to receive(:rand).and_return(0.3)
        transaction = described_class.start_transaction(op: "rack.request", name: "/api")
        expect(transaction.sampled).to eq(false)
      end

      it "gives other paths 0.1 of rate" do
        allow(Random).to receive(:rand).and_return(0.05)
        transaction = described_class.start_transaction(op: "rack.request", name: "/orders")
        expect(transaction.sampled).to eq(true)

        allow(Random).to receive(:rand).and_return(0.2)
        transaction = described_class.start_transaction(op: "rack.request", name: "/orders")
        expect(transaction.sampled).to eq(false)
      end

      it "gives sidekiq ops 0.01 of rate" do
        allow(Random).to receive(:rand).and_return(0.005)
        transaction = described_class.start_transaction(op: "sidekiq")
        expect(transaction.sampled).to eq(true)

        allow(Random).to receive(:rand).and_return(0.02)
        transaction = described_class.start_transaction(op: "sidekiq")
        expect(transaction.sampled).to eq(false)
      end
    end

    context "when tracing is enabled" do
      before do
        Sentry.configuration.traces_sample_rate = 1.0
      end

      it "starts a new transaction" do
        transaction = described_class.start_transaction(op: "foo")
        expect(transaction).to be_a(Sentry::Transaction)
        expect(transaction.op).to eq("foo")
      end

      context "when given an transaction object" do
        it "adds sample decision to it" do
          transaction = Sentry::Transaction.new(hub: Sentry.get_current_hub)

          described_class.start_transaction(transaction: transaction)

          expect(transaction.sampled).to eq(true)
        end

        it "provides proper sampling context to the traces_sampler" do
          transaction = Sentry::Transaction.new(op: "foo", hub: Sentry.get_current_hub)

          context = nil
          Sentry.configuration.traces_sampler = lambda do |sampling_context|
            context = sampling_context
          end

          described_class.start_transaction(transaction: transaction)

          expect(context[:parent_sampled]).to be_nil
          expect(context[:transaction_context][:op]).to eq("foo")
        end

        it "passes parent_sampled to the sampling_context" do
          transaction = Sentry::Transaction.new(parent_sampled: true, hub: Sentry.get_current_hub)

          context = nil
          Sentry.configuration.traces_sampler = lambda do |sampling_context|
            context = sampling_context
          end

          described_class.start_transaction(transaction: transaction)

          expect(context[:parent_sampled]).to eq(true)
        end
      end

      context "when given a custom_sampling_context" do
        it "takes that into account" do
          context = nil
          Sentry.configuration.traces_sampler = lambda do |sampling_context|
            context = sampling_context
          end

          described_class.start_transaction(custom_sampling_context: { foo: "bar" })

          expect(context).to include({ foo: "bar" })
        end
      end

      context "when event reporting is not enabled" do
        let(:string_io) { StringIO.new }
        let(:logger) do
          ::Logger.new(string_io)
        end
        before do
          Sentry.configuration.logger = logger
          Sentry.configuration.enabled_environments = ["production"]
        end

        it "sets @sampled to false and return" do
          transaction = described_class.start_transaction
          expect(transaction).to eq(nil)
          expect(string_io.string).not_to include(
            "[Tracing]"
          )
        end
      end
    end

    context "when tracing is disabled" do
      it "returns nil" do
        expect(described_class.start_transaction(op: "foo")).to eq(nil)
      end
    end
  end

  describe ".last_event_id" do
    it "gets the last_event_id from current_hub" do
      expect(described_class.get_current_hub).to receive(:last_event_id)

      described_class.last_event_id
    end
  end

  describe ".add_breadcrumb" do
    it "adds breadcrumb to the current scope" do
      crumb = Sentry::Breadcrumb.new(message: "foo")
      described_class.add_breadcrumb(crumb)

      expect(described_class.get_current_scope.breadcrumbs.peek).to eq(crumb)
    end

    it "triggers before_breadcrumb callback" do
      Sentry.configuration.before_breadcrumb = lambda do |breadcrumb, hint|
        nil
      end

      crumb = Sentry::Breadcrumb.new(message: "foo")

      described_class.add_breadcrumb(crumb)

      expect(described_class.get_current_scope.breadcrumbs.peek).to eq(nil)
    end
  end

  describe ".set_tags" do
    it "adds tags to the current scope" do
      described_class.set_tags(foo: "bar")

      expect(described_class.get_current_scope.tags).to eq(foo: "bar")
    end
  end

  describe ".set_extras" do
    it "adds extras to the current scope" do
      described_class.set_extras(foo: "bar")

      expect(described_class.get_current_scope.extra).to eq(foo: "bar")
    end
  end

  describe ".set_context" do
    it "adds context to the current scope" do
      described_class.set_context("character", { name: "John", age: 25 })

      expect(described_class.get_current_scope.contexts).to include("character" => { name: "John", age: 25 })
    end
  end

  describe ".set_user" do
    it "adds user to the current scope" do
      described_class.set_user(id: 1)

      expect(described_class.get_current_scope.user).to eq(id: 1)
    end
  end

  describe ".csp_report_uri" do
    it "returns nil if the SDK is not initialized" do
      described_class.instance_variable_set(:@main_hub, nil)
      expect(described_class.csp_report_uri).to eq(nil)
    end

    it "returns the csp_report_uri generated from the main Configuration" do
      expect(Sentry.configuration).to receive(:csp_report_uri).and_call_original

      expect(described_class.csp_report_uri).to eq("http://sentry.localdomain/api/42/security/?sentry_key=12345&sentry_environment=default")
    end
  end

  describe 'release detection' do
    let(:fake_root) { "/tmp/sentry/" }

    before do
      allow(File).to receive(:directory?).and_return(false)
      allow_any_instance_of(Sentry::Configuration).to receive(:project_root).and_return(fake_root)
      ENV["SENTRY_DSN"] = DUMMY_DSN
    end

    subject { described_class.configuration }

    it 'defaults to nil' do
      described_class.init
      expect(described_class.configuration.release).to eq(nil)
    end

    it "respects user's config" do
      described_class.init do |config|
        config.release = "foo"
      end

      expect(described_class.configuration.release).to eq("foo")
    end

    it 'uses `SENTRY_RELEASE` env variable' do
      ENV['SENTRY_RELEASE'] = 'v1'

      described_class.init
      expect(described_class.configuration.release).to eq('v1')

      ENV.delete('SENTRY_CURRENT_ENV')
    end

    context "when the DSN is not set" do
      before do
        ENV.delete("SENTRY_DSN")
      end

      it "doesn't detect release" do
        ENV['SENTRY_RELEASE'] = 'v1'

        described_class.init
        expect(described_class.configuration.release).to eq(nil)

        ENV.delete('SENTRY_CURRENT_ENV')
      end
    end

    context "when the SDK is not enabled under the current env" do
      it "doesn't detect release" do
        ENV['SENTRY_RELEASE'] = 'v1'

        described_class.init do |config|
          config.enabled_environments = "production"
        end

        expect(described_class.configuration.release).to eq(nil)

        ENV.delete('SENTRY_CURRENT_ENV')
      end
    end

    context "when git is available" do
      before do
        allow(File).to receive(:directory?).and_return(false)
        allow(File).to receive(:directory?).with(".git").and_return(true)
      end
      it 'gets release from git' do
        allow(Sentry).to receive(:`).with("git rev-parse --short HEAD 2>&1").and_return("COMMIT_SHA")

        described_class.init
        expect(described_class.configuration.release).to eq('COMMIT_SHA')
      end
    end

    context "when Capistrano is available" do
      let(:revision) { "2019010101000" }

      before do
        Dir.mkdir(fake_root) unless Dir.exist?(fake_root)
        File.write(filename, file_content)
      end

      after do
        File.delete(filename)
        Dir.delete(fake_root)
      end

      context "when the REVISION file is present" do
        let(:filename) do
          File.join(fake_root, "REVISION")
        end
        let(:file_content) { revision }

        it "gets release from the REVISION file" do
          described_class.init
          expect(described_class.configuration.release).to eq(revision)
        end
      end

      context "when the revisions.log file is present" do
        let(:filename) do
          File.join(fake_root, "..", "revisions.log")
        end
        let(:file_content) do
          "Branch master (at COMMIT_SHA) deployed as release #{revision} by alice"
        end

        it "gets release from the REVISION file" do
          described_class.init
          expect(described_class.configuration.release).to eq(revision)
        end
      end
    end

    context "when running on heroku" do
      before do
        allow(File).to receive(:directory?).and_return(false)
        allow(File).to receive(:directory?).with("/etc/heroku").and_return(true)
      end

      context "when it's on heroku ci" do
        it "returns nil" do
          begin
            original_ci_val = ENV["CI"]
            ENV["CI"] = "true"

            described_class.init
            expect(described_class.configuration.release).to eq(nil)
          ensure
            ENV["CI"] = original_ci_val
          end
        end
      end

      context "when it's not on heroku ci" do
        around do |example|
          begin
            original_ci_val = ENV["CI"]
            ENV["CI"] = nil

            example.run
          ensure
            ENV["CI"] = original_ci_val
          end
        end

        it "returns nil + logs an warning if HEROKU_SLUG_COMMIT is not set" do
          string_io = StringIO.new
          logger = Logger.new(string_io)

          described_class.init do |config|
            config.logger = logger
          end

          expect(described_class.configuration.release).to eq(nil)
          expect(string_io.string).to include(Sentry::Configuration::HEROKU_DYNO_METADATA_MESSAGE)
        end

        it "returns HEROKU_SLUG_COMMIT" do
          begin
            ENV["HEROKU_SLUG_COMMIT"] = "REVISION"

            described_class.init
            expect(described_class.configuration.release).to eq("REVISION")
          ensure
            ENV["HEROKU_SLUG_COMMIT"] = nil
          end
        end
      end

      context "when having an error detecting the release" do
        it "logs the error" do
          string_io = StringIO.new
          logger = Logger.new(string_io)
          allow_any_instance_of(Sentry::Configuration).to receive(:detect_release_from_git).and_raise(TypeError.new)

          described_class.init do |config|
            config.logger = logger
          end

          expect(string_io.string).to include("ERROR -- sentry: Error detecting release: TypeError")
        end
      end
    end
  end

end
