require "spec_helper"

RSpec.describe Sentry::Scope do
  let(:new_breadcrumb) do
    new_breadcrumb = Sentry::Breadcrumb.new
    new_breadcrumb.message = "foo"
    new_breadcrumb
  end

  let(:configuration) { Sentry::Configuration.new }
  let(:client) { Sentry::Client.new(configuration) }
  let(:hub) do
    Sentry::Hub.new(client, subject)
  end

  describe "#initialize" do
    it "contains correct defaults" do
      expect(subject.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(subject.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version, :machine])
      expect(subject.contexts.dig(:runtime, :version)).to match(/ruby/)
      expect(subject.extra).to eq({})
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.fingerprint).to eq([])
      expect(subject.transaction_names).to eq([])
      expect(subject.transaction_sources).to eq([])
      expect(subject.propagation_context).to be_a(Sentry::PropagationContext)
    end

    it "allows setting breadcrumb buffer's size limit" do
      scope = described_class.new(max_breadcrumbs: 10)
      expect(scope.breadcrumbs.buffer.count).to eq(10)
    end
  end

  describe "#dup" do
    it "copies the values instead of just references to values" do
      copy = subject.dup

      copy.breadcrumbs.record(new_breadcrumb)
      copy.contexts.merge!(os: {})
      copy.extra.merge!(foo: "bar")
      copy.tags.merge!(foo: "bar")
      copy.user.merge!(foo: "bar")
      copy.transaction_names << "foo"
      copy.transaction_sources << :url
      copy.fingerprint << "bar"

      expect(subject.breadcrumbs.to_hash).to eq({ values: [] })
      expect(subject.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version, :machine])
      expect(subject.contexts.dig(:runtime, :version)).to match(/ruby/)
      expect(subject.extra).to eq({})
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.fingerprint).to eq([])
      expect(subject.transaction_names).to eq([])
      expect(subject.transaction_sources).to eq([])
      expect(subject.span).to eq(nil)
    end

    it "deep-copies span as well" do
      perform_basic_setup

      span = Sentry::Transaction.new(sampled: true, hub: hub)
      subject.set_span(span)
      copy = subject.dup

      span.start_child

      expect(copy.span.span_recorder.spans.count).to eq(1)
      expect(subject.span.span_recorder.spans.count).to eq(2)
    end
  end

  describe "#add_breadcrumb" do
    it "adds the breadcrumb to the buffer" do
      expect(subject.breadcrumbs.empty?).to eq(true)

      subject.add_breadcrumb(new_breadcrumb)

      expect(subject.breadcrumbs.peek).to eq(new_breadcrumb)
    end
  end

  describe "#clear_breadcrumbs" do
    subject do
      described_class.new(max_breadcrumbs: 10)
    end

    before do
      subject.add_breadcrumb(new_breadcrumb)

      expect(subject.breadcrumbs.peek).to eq(new_breadcrumb)
    end

    it "clears all breadcrumbs by replacing the buffer object" do
      subject.clear_breadcrumbs

      expect(subject.breadcrumbs.empty?).to eq(true)
      expect(subject.breadcrumbs.buffer.size).to eq(10)
    end
  end

  describe "#add_event_processor" do
    it "adds the processor to the scope" do
      expect(subject.event_processors.count).to eq(0)

      expect do
        subject.add_event_processor { |e| e }
      end.to change { subject.event_processors.count }.by(1)
    end
  end

  describe ".add_global_event_processor" do
    after { described_class.global_event_processors.clear }

    it "adds the global processor to the scope" do
      expect(described_class.global_event_processors.count).to eq(0)

      expect do
        described_class.add_global_event_processor { |e| e }
      end.to change { described_class.global_event_processors.count }.by(1)
    end
  end

  describe "#clear" do
    it "resets the scope's data" do
      subject.set_tags({foo: "bar"})
      subject.set_extras({additional_info: "hello"})
      subject.set_user({id: 1})
      subject.set_transaction_name("WelcomeController#index")
      subject.set_span(Sentry::Transaction.new(op: "foo", hub: hub))
      subject.set_fingerprint(["foo"])
      scope_id = subject.object_id

      subject.clear

      expect(subject.object_id).to eq(scope_id)
      expect(subject.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(subject.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version, :machine])
      expect(subject.contexts.dig(:runtime, :version)).to match(/ruby/)
      expect(subject.extra).to eq({})
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.fingerprint).to eq([])
      expect(subject.transaction_names).to eq([])
      expect(subject.transaction_sources).to eq([])
      expect(subject.span).to eq(nil)
    end
  end

  describe "#get_transaction & #get_span" do
    before do
      # because initializing transactions requires an active hub
      perform_basic_setup
    end

    let(:transaction) do
      Sentry::Transaction.new(op: "parent", hub: hub)
    end

    context "with span in the scope" do
      let(:span) do
        transaction.start_child(op: "child")
      end

      before do
        subject.set_span(span)
      end

      it "gets the span from the scope" do
        expect(subject.get_span).to eq(span)
      end

      it "gets the transaction from the span recorder" do
        expect(subject.get_transaction).to eq(transaction)
      end
    end

    context "without span in the scope" do
      it "returns nil" do
        expect(subject.get_transaction).to eq(nil)
      end

      it "returns nil" do
        expect(subject.get_span).to eq(nil)
      end
    end
  end

  describe "#apply_to_event" do
    before { perform_basic_setup }

    let(:client) do
      Sentry.get_current_client
    end

    subject do
      scope = described_class.new
      scope.set_tags({foo: "bar"})
      scope.set_extras({additional_info: "hello"})
      scope.set_user({id: 1})
      scope.set_transaction_name("WelcomeController#index", source: :view)
      scope.set_fingerprint(["foo"])
      scope
    end

    let(:event) do
      client.event_from_message("test message")
    end

    it "applies the contextual data to event" do
      subject.apply_to_event(event)
      expect(event.tags).to eq({foo: "bar"})
      expect(event.user).to eq({id: 1})
      expect(event.extra).to eq({additional_info: "hello"})
      expect(event.transaction).to eq("WelcomeController#index")
      expect(event.transaction_info).to eq({ source: :view })
      expect(event.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(event.fingerprint).to eq(["foo"])
      expect(event.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version, :machine])
      expect(event.contexts.dig(:runtime, :version)).to match(/ruby/)
    end

    it "doesn't override event's pre-existing data" do
      event.tags = {foo: "baz"}
      event.user = {id: 2}
      event.extra = {additional_info: "nothing"}
      event.contexts = {os: nil}

      subject.apply_to_event(event)
      expect(event.tags).to eq({foo: "baz"})
      expect(event.user).to eq({id: 2})
      expect(event.extra[:additional_info]).to eq("nothing")
      expect(event.contexts[:os]).to eq(nil)
    end

    it "applies event processors to the event" do
      subject.add_event_processor do |event, hint|
        event.tags = { processed: true }
        event.extra = hint
        event
      end

      subject.apply_to_event(event, { foo: "bar" })

      expect(event.tags).to eq({ processed: true })
      expect(event.extra).to eq({ foo: "bar" })
    end

    context "with global event processor" do
      before do
        described_class.add_global_event_processor do |event, hint|
          event.tags = { bar: 99 }
          event.extra = hint
          event
        end
      end

      after { described_class.global_event_processors.clear }

      it "applies global event processors to the event" do
        subject.apply_to_event(event, { foo: 42 })

        expect(event.tags).to eq({ bar: 99 })
        expect(event.extra).to eq({ foo: 42 })
      end

      it "scope event processors take precedence over global event processors" do
        subject.add_event_processor do |event, hint|
          event.tags = { foo: 42 }
          event
        end

        subject.apply_to_event(event)
        expect(event.tags).to eq({ foo: 42 })
      end
    end

    it "sets trace context from span if there's a span" do
      transaction = Sentry::Transaction.new(op: "foo", hub: hub)
      subject.set_span(transaction)

      subject.apply_to_event(event)

      expect(event.contexts[:trace]).to eq(transaction.get_trace_context)
      expect(event.contexts.dig(:trace, :op)).to eq("foo")
    end

    it "sets trace context and dynamic_sampling_context from propagation context if there's no span" do
      subject.apply_to_event(event)
      expect(event.contexts[:trace]).to eq(subject.propagation_context.get_trace_context)
      expect(event.dynamic_sampling_context).to eq(subject.propagation_context.get_dynamic_sampling_context)
    end

    context "with Rack", rack: true do
      let(:env) do
        Rack::MockRequest.env_for("/test", {})
      end

      subject do
        scope = described_class.new
        scope.set_rack_env(env)
        scope
      end

      it "sets the request info the Event" do
        subject.apply_to_event(event)

        expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
      end
    end
  end

  describe "#generate_propagation_context" do
    it "initializes new propagation context without env" do
      expect(Sentry::PropagationContext).to receive(:new).with(subject, nil)
      subject.generate_propagation_context
    end

    it "initializes new propagation context without env" do
      env = { foo: 42 }
      expect(Sentry::PropagationContext).to receive(:new).with(subject, env)
      subject.generate_propagation_context(env)
    end
  end
end
