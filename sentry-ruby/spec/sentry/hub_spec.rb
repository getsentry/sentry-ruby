require 'spec_helper'

RSpec.describe Sentry::Hub do
  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end
  let(:configuration) do
    config = Sentry::Configuration.new
    config.dsn = Sentry::TestHelper::DUMMY_DSN
    config.transport.transport_class = Sentry::DummyTransport
    config.background_worker_threads = 0
    config.logger = logger
    config
  end
  let(:client) { Sentry::Client.new(configuration) }
  let(:transport) { client.transport }
  let(:scope) { Sentry::Scope.new }

  before do
    Sentry.background_worker = Sentry::BackgroundWorker.new(configuration)
  end

  subject { described_class.new(client, scope) }

  shared_examples "capture_helper" do
    context "with sending_allowed? condition" do
      before do
        expect(configuration).to receive(:sending_allowed?).and_return(false)
      end

      it "doesn't send the event nor assign last_event_id" do
        subject.send(capture_helper, *capture_subject)

        expect(transport.events).to be_empty
        expect(subject.last_event_id).to eq(nil)
      end
    end

    context "with custom attributes" do
      it "updates the event with custom attributes" do
        subject.send(capture_helper, *capture_subject, tags: { foo: "bar" })

        event = transport.events.last
        expect(event.tags).to eq({ foo: "bar" })
      end

      it "accepts custom level" do
        subject.send(capture_helper, *capture_subject, level: :info)

        event = transport.events.last
        expect(event.level).to eq(:info)
      end

      it "merges the contexts/tags/extrac with what the scope already has" do
        scope.set_tags(old_tag: true)
        scope.set_contexts({ character: { name: "John", age: 25 }})
        scope.set_extras(old_extra: true)

        subject.send(
          capture_helper,
          *capture_subject,
          tags: { new_tag: true },
          contexts: { another_character: { name: "Jane", age: 20 }},
          extra: { new_extra: true }
        )

        event = transport.events.last
        expect(event.tags).to eq({ new_tag: true, old_tag: true })
        expect(event.contexts).to include(
          {
            character: { name: "John", age: 25 },
            another_character: { name: "Jane", age: 20 }
          }
        )
        expect(event.extra).to eq({ new_extra: true, old_extra: true })

        expect(scope.tags).to eq(old_tag: true)
        expect(scope.contexts).to include({ character: { name: "John", age: 25 }})
        expect(scope.extra).to eq(old_extra: true)
      end
    end

    context "with custom scope" do
      let(:new_scope) do
        scope = Sentry::Scope.new
        scope.set_tags({ custom_scope: true })
        scope
      end

      it "accepts a custom scope" do
        subject.send(capture_helper, *capture_subject, scope: new_scope)

        event = transport.events.last
        expect(event.tags).to eq({ custom_scope: true })
      end
    end

    context "with a block" do
      before do
        scope.set_tags({ original_scope: true })
      end

      it 'yields the scope to a passed block' do
        subject.send(capture_helper, *capture_subject) do |scope|
          scope.set_tags({ temporary_scope: true })
        end

        event = transport.events.last
        expect(event.tags).to eq({ original_scope: true, temporary_scope: true })
      end
    end

    context "with a hint" do
      it "passes the hint all the way down to Client#send_event" do
        hint = nil
        configuration.before_send = ->(event, h) { hint = h }

        subject.send(capture_helper, *capture_subject, hint: {foo: "bar"})

        case capture_subject
        when String
          expect(hint).to eq({message: capture_subject, foo: "bar"})
        when Exception
          expect(hint).to eq({exception: capture_subject, foo: "bar"})
        when Array
          expect(hint).to eq({slug: capture_subject.first, foo: "bar"})
        else
          expect(hint).to eq({foo: "bar"})
        end
      end
    end
  end

  describe '#capture_message' do
    let(:message) { "Test message" }

    it "returns an Event instance" do
      expect(subject.capture_message(message)).to be_a(Sentry::ErrorEvent)
    end

    it 'initializes an Event, and sends it via the Client' do
      expect do
        subject.capture_message(message)
      end.to change { transport.events.count }.by(1)
    end

    it "takes backtrace option" do
      event = subject.capture_message(message, backtrace: ["#{__FILE__}:10:in `foo'"])
      event_hash = event.to_hash
      expect(event_hash.dig(:threads, :values, 0, :stacktrace, :frames, 0, :function)).to eq("foo")
    end

    it "raises error when passing a non-string object" do
      expect do
        subject.capture_message(1)
      end.to raise_error(ArgumentError, 'expect the argument to be a String, got Integer (1)')
    end

    it "assigns default backtrace with caller" do
      event = subject.capture_message(message)
      event_hash = event.to_hash
      expect(event_hash.dig(:threads, :values, 0, :stacktrace, :frames, 0, :function)).to eq("<main>")
    end

    it_behaves_like "capture_helper" do
      let(:capture_helper) { :capture_message }
      let(:capture_subject) { message }
    end
  end

  describe '#capture_check_in' do
    let(:slug) { "test_slug" }

    it "raises error when passing a non-string slug" do
      expect do
        subject.capture_check_in(1, :ok)
      end.to raise_error(ArgumentError, 'expect the argument to be a String, got Integer (1)')
    end

    it "raises error when passing an invalid status" do
      expect do
        subject.capture_check_in(slug, "bla")
      end.to raise_error(ArgumentError, 'expect the argument to be one of :ok or :in_progress or :error, got "bla"')
    end

    it "raises error when passing an invalid status symbol" do
      expect do
        subject.capture_check_in(slug, :bla)
      end.to raise_error(ArgumentError, 'expect the argument to be one of :ok or :in_progress or :error, got :bla')
    end

    it "returns a check_in id" do
      check_in_id = subject.capture_check_in(slug, :ok)
      expect(check_in_id).to be_a(String)
      expect(check_in_id.length).to eq(32)
    end

    it "initializes an Event, and sends it via the Client" do
      expect do
        subject.capture_check_in(slug, :ok)
      end.to change { transport.events.count }.by(1)
    end

    it "populates the event hash correctly" do
      subject.capture_check_in(
        slug,
        :ok,
        duration: 30,
        check_in_id: "xxx-yyy",
        monitor_config: Sentry::Cron::MonitorConfig.from_crontab("* * * * *")
      )

      event = transport.events.last.to_hash
      expect(event).to include(
        monitor_slug: slug,
        status: :ok,
        check_in_id: "xxx-yyy",
        duration: 30,
        monitor_config: { schedule: { type: :crontab, value: "* * * * *" } }
      )
    end

    it_behaves_like "capture_helper" do
      let(:capture_helper) { :capture_check_in }
      let(:capture_subject) { [slug, :ok] }
    end
  end

  describe '#capture_exception' do
    let(:exception) { ZeroDivisionError.new("divided by 0") }

    it "returns an Event instance" do
      expect(subject.capture_exception(exception)).to be_a(Sentry::ErrorEvent)
    end

    it 'initializes an Event, and sends it via the Client' do
      expect do
        subject.capture_exception(exception)
      end.to change { transport.events.count }.by(1)
    end

    if RUBY_PLATFORM == "java"
      context 'when called under jRuby' do
        let(:exception) do
          begin
            raise java.lang.OutOfMemoryError, "A Java error"
          rescue Exception => exception
            exception
          end
        end


      it "raises error when passing a non-exception object" do
        expect do
          subject.capture_exception("String")
        end.to raise_error(ArgumentError, 'expect the argument to be a Exception or Java::JavaLang::Throwable, got String ("String")')
      end

        it 'allows a java error object to be passed' do
          expect do
            subject.capture_exception(exception)
          end.not_to raise_error
        end
      end
    else
      it "raises error when passing a non-exception object" do
        expect do
          subject.capture_exception("String")
        end.to raise_error(ArgumentError, 'expect the argument to be a Exception, got String ("String")')
      end
    end

    # see https://github.com/getsentry/sentry-ruby/issues/1323
    it "don't causes error when the exception's message is nil" do
      allow(exception).to receive(:message)

      expect do
        subject.capture_exception(exception)
      end.to change { transport.events.count }.by(1)
    end

    it "takes ignore_exclusions hint" do
      configuration.excluded_exceptions << exception.class

      expect do
        subject.capture_exception(exception, hint: { ignore_exclusions: true })
      end.to change { transport.events.count }.by(1)
    end

    it_behaves_like "capture_helper" do
      let(:capture_helper) { :capture_exception }
      let(:capture_subject) { exception }
    end
  end

  describe '#capture_event' do
    let(:exception) { ZeroDivisionError.new("divided by 0") }
    let!(:event) do
      client.event_from_exception(exception)
    end

    it "returns an Event instance" do
      expect(subject.capture_event(event)).to be_a(Sentry::ErrorEvent)
    end

    it 'sends the event via client' do
      expect do
        subject.capture_event(event)
      end.to change { transport.events.count }.by(1)
    end

    it "raises error when passing a non-exception object" do
      expect do
        subject.capture_event("String")
      end.to raise_error(ArgumentError, 'expect the argument to be a Sentry::Event, got String ("String")')
    end

    it "doesn't log event payload" do
      subject.capture_event(event)

      expect(string_io.string).not_to include(event.to_json_compatible.to_s)
    end

    context "in debug mode" do
      before do
        configuration.debug = true
      end

      it "logs event payload" do
        subject.capture_event(event)

        expect(string_io.string).to include(event.to_json_compatible.to_s)
      end
    end

    context "when event is a transaction" do
      it "transaction.set_context merges and takes precedence over scope.set_context" do
        scope.set_context(:foo, { val: 42 })
        scope.set_context(:bar, { val: 43 })

        transaction = Sentry::Transaction.new(hub: subject, name: 'test')
        transaction.set_context(:foo, { val: 44 })
        transaction.set_context(:baz, { val: 45 })

        transaction_event = subject.current_client.event_from_transaction(transaction)
        subject.capture_event(transaction_event)

        event = transport.events.last
        expect(event.contexts[:foo]). to eq({ val: 44 })
        expect(event.contexts[:bar]). to eq({ val: 43 })
        expect(event.contexts[:baz]). to eq({ val: 45 })
      end
    end

    it_behaves_like "capture_helper" do
      let(:capture_helper) { :capture_event }
      let(:capture_subject) { event }
    end
  end

  describe "#with_scope" do
    it "builds a temporary scope" do
      inner_event = nil
      scope.set_tags({ level: 1 })

      subject.with_scope do |scope|
        scope.set_tags({ level: 2 })
        inner_event = subject.capture_message("Inner event")
      end

      outter_event = subject.capture_message("Outter event")

      expect(inner_event.tags).to eq({ level: 2 })
      expect(outter_event.tags).to eq({ level: 1 })
    end

    it "doesn't leak data mutation" do
      inner_event = nil
      scope.set_tags({ level: 1 })

      subject.with_scope do |scope|
        scope.tags[:level] = 2
        inner_event = subject.capture_message("Inner event")
      end

      outter_event = subject.capture_message("Outter event")

      expect(inner_event.tags).to eq({ level: 2 })
      expect(outter_event.tags).to eq({ level: 1 })
    end
  end

  describe "#add_breadcrumb" do
    let(:new_breadcrumb) do
      new_breadcrumb = Sentry::Breadcrumb.new
      new_breadcrumb.message = "foo"
      new_breadcrumb
    end

    let(:peek_crumb) do
      subject.current_scope.breadcrumbs.peek
    end

    it "adds the breadcrumb to the buffer" do
      expect(subject.current_scope.breadcrumbs.empty?).to eq(true)

      subject.add_breadcrumb(new_breadcrumb)

      expect(peek_crumb).to eq(new_breadcrumb)
    end

    context "with before_breadcrumb" do
      before do
        configuration.before_breadcrumb = lambda do |breadcrumb, hint|
          breadcrumb.message = hint[:message]
          breadcrumb
        end
      end

      it "adds the updated breadcrumb" do
        subject.add_breadcrumb(new_breadcrumb, hint: { message: "hey!" })

        expect(peek_crumb.message).to eq("hey!")
      end

      context "when before_breadcrumb returns nil" do
        before do
          configuration.before_breadcrumb = lambda do |breadcrumb, hint|
            nil
          end
        end

        it "doesn't add anything" do
          subject.add_breadcrumb(new_breadcrumb)

          expect(peek_crumb).to eq(nil)
        end
      end
    end

    context "when the SDK is not activated in the current environment" do
      before do
        configuration.enabled_environments = ["production"]
      end

      it "doesn't record breadcrumbs" do
        subject.add_breadcrumb(new_breadcrumb)

        expect(peek_crumb).to eq(nil)
      end
    end
  end

  describe "#new_from_top" do
    it "initializes a different hub with current hub's top layer" do
      new_hub = subject.new_from_top

      expect(new_hub).not_to eq(subject)
      expect(new_hub.current_client).to eq(subject.current_client)
      expect(new_hub.current_scope).to eq(subject.current_scope)
    end
  end

  describe "#clone" do
    it "creates a new hub with the current hub's top layer" do
      new_hub = subject.clone

      expect(new_hub).not_to eq(subject)
      expect(new_hub.current_client).to eq(subject.current_client)
      expect(new_hub.current_scope).to be_a(Sentry::Scope)
      expect(new_hub.current_scope).not_to eq(subject.current_scope)
    end
  end

  describe "#bind_client & #unbind_client" do
    let(:new_client) { Sentry::Client.new(configuration) }

    describe "#bind_client" do
      it "binds the new client with the hub" do
        subject.bind_client(new_client)

        expect(subject.current_client).to eq(new_client)
      end

      it "doesn't change the scope" do
        old_scope = subject.current_scope

        subject.bind_client(new_client)

        expect(subject.current_scope).to eq(old_scope)
      end
    end
  end

  describe "#pop_scope" do
    it "pops the current scope" do
      expect(subject.current_scope).to eq(scope)
      subject.pop_scope
      expect(subject.current_scope).to eq(nil)
    end
  end

  describe "#push_scope" do
    it "pushes a new scope to the scope stack" do
      expect(subject.current_scope).to eq(scope)
      subject.push_scope
      expect(subject.current_scope).to be_a(Sentry::Scope)
      expect(subject.current_scope).not_to eq(scope)
    end

    it "clones the new scope from the current scope" do
      scope.set_tags({ foo: "bar" })

      expect(subject.current_scope).to eq(scope)

      subject.push_scope

      expect(subject.current_scope).not_to eq(scope)
      expect(subject.current_scope.tags).to eq({ foo: "bar" })
    end

    context "when the current_scope is nil" do
      before do
        subject.pop_scope
        expect(subject.current_scope).to eq(nil)
      end
      it "creates a new scope" do
        scope.set_tags({ foo: "bar" })

        subject.push_scope

        expect(subject.current_scope).not_to eq(scope)
        expect(subject.current_scope.tags).to eq({})
      end
    end
  end

  describe '#configure_scope' do
    it "yields the current scope" do
      scope = nil

      subject.configure_scope { |s| scope = s }

      expect(scope).to eq(subject.current_scope)
    end
  end

  describe '#last_event_id' do
    let(:message) { "Test message" }

    it 'sends the result of Event.capture_type' do
      expect(client).to receive(:send_event)

      event = subject.capture_message("Test message")

      expect(subject.last_event_id).to eq(event.event_id)
    end

    it 'only records last_event_id for error events' do
      exception = ZeroDivisionError.new("divided by 0")
      transaction = Sentry::Transaction.new(name: "test transaction", op: "rack.request", hub: subject)

      error_event = client.event_from_exception(exception)
      transaction_event = client.event_from_transaction(transaction)
      check_in_event = client.event_from_check_in("test_slug", :ok)

      subject.capture_event(error_event)
      subject.capture_event(transaction_event)
      subject.capture_event(check_in_event)

      expect(subject.last_event_id).to eq(error_event.event_id)
      expect(subject.last_event_id).not_to eq(transaction_event.event_id)
      expect(subject.last_event_id).not_to eq(check_in_event.event_id)
    end
  end

  describe "#with_background_worker_disabled" do
    before do
      configuration.background_worker_threads = 5
      Sentry.background_worker = Sentry::BackgroundWorker.new(configuration)
      configuration.before_send = lambda do |event, _hint|
        sleep 0.5
        event
      end
    end

    it "disables async event sending temporarily" do
      subject.with_background_worker_disabled do
        subject.capture_message("foo")
      end

      expect(transport.events.count).to eq(1)
    end

    it "returns the original execution result" do
      result = subject.with_background_worker_disabled do
        "foo"
      end

      expect(result).to eq("foo")
    end

    it "doesn't interfere events outside of the block" do
      subject.with_background_worker_disabled {}

      subject.capture_message("foo")
      expect(transport.events.count).to eq(0)
    end

    it "resumes the backgrounding state even with exception" do
      subject.with_background_worker_disabled do
        raise "foo"
      end rescue nil

      subject.capture_message("foo")
      expect(transport.events.count).to eq(0)
    end
  end
end
