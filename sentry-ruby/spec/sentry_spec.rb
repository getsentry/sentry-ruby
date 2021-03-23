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
          transaction = Sentry::Transaction.new

          described_class.start_transaction(transaction: transaction)

          expect(transaction.sampled).to eq(true)
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
end
