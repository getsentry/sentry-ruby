require 'spec_helper'

RSpec.describe Sentry::Hub do
  let(:configuration) do
    config = Sentry::Configuration.new
    config.dsn = DUMMY_DSN
    config
  end
  let(:client) { Sentry::Client.new(configuration) }
  let(:scope) { Sentry::Scope.new }

  subject { described_class.new(client, scope) }

  before do
    allow(client).to receive(:send_event)
  end

  describe '#capture_message' do
    let(:message) { "Test message" }
    let(:options) { { tags: { foo: "bar" }, server_name: "foo.local" } }

    it 'initializes an Event, and sends it via the Client' do
      expect(client).to receive(:send_event)

      subject.capture_message(message, options)
    end

    it 'yields the event to a passed block' do
      expect(client).to receive(:send_event)

      event = nil
      subject.capture_message(message, **options) { |e| event = e }

      expect(event.tags).to eq({ foo: "bar" })
      expect(event.server_name).to eq("foo.local")
    end
  end

  describe '#capture_exception' do
    let(:exception) { ZeroDivisionError.new("divided by 0") }
    let(:options) { { tags: { foo: "bar" }, server_name: "foo.local" } }

    it 'initializes an Event, and sends it via the Client' do
      expect(client).to receive(:send_event)

      subject.capture_exception(exception, options)
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

    it "adds the breadcrumb to the buffer" do
      expect(subject.current_scope.breadcrumbs.empty?).to eq(true)

      subject.add_breadcrumb(new_breadcrumb)

      expect(subject.current_scope.breadcrumbs.peek).to eq(new_breadcrumb)
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

      expect(subject.last_event_id).to eq(event.id)
    end
  end
end
