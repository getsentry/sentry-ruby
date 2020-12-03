RSpec.describe Sentry do
  before do
    Sentry.init do |config|
      config.dsn = DUMMY_DSN
    end
  end

  let(:event) do
    Sentry::Event.new(configuration: Sentry::Configuration.new)
  end

  describe ".init" do
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

  describe ".capture_event" do
    it "sends the event via current hub" do
      expect(described_class.get_current_hub).to receive(:capture_event).with(event)

      described_class.capture_event(event)
    end
  end

  describe ".capture_exception" do
    let(:exception) { ZeroDivisionError.new("divided by 0") }

    it "sends the message via current hub" do
      expect(described_class.get_current_hub).to receive(:capture_exception).with(exception, tags: { foo: "baz" })

      described_class.capture_exception(exception, tags: { foo: "baz" })
    end

    it "doesn't do anything if the exception is excluded" do
      Sentry.get_current_client.configuration.excluded_exceptions = ["ZeroDivisionError"]

      result = described_class.capture_exception(exception)

      expect(result).to eq(nil)
    end
  end

  describe ".start_transaction" do
    it "starts a new transaction" do
      transaction = described_class.start_transaction(op: "foo")
      expect(transaction).to be_a(Sentry::Transaction)
      expect(transaction.op).to eq("foo")
    end

    context "when given an transaction object" do
      it "adds sample decision to it" do
        transaction = Sentry::Transaction.new

        described_class.start_transaction(transaction: transaction)

        expect(transaction.sampled).to eq(false)
      end
    end
  end

  describe ".capture_message" do
    it "sends the message via current hub" do
      expect(described_class.get_current_hub).to receive(:capture_message).with("Test", tags: { foo: "baz" })

      described_class.capture_message("Test", tags: { foo: "baz" })
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

  describe ".set_user" do
    it "adds user to the current scope" do
      described_class.set_user(id: 1)

      expect(described_class.get_current_scope.user).to eq(id: 1)
    end
  end
end
