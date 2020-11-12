require "spec_helper"

RSpec.describe Sentry::Scope do
  let(:new_breadcrumb) do
    new_breadcrumb = Sentry::Breadcrumb.new
    new_breadcrumb.message = "foo"
    new_breadcrumb
  end

  describe "#initialize" do
    it "contains correct defaults" do
      expect(subject.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(subject.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version])
      expect(subject.contexts.dig(:runtime, :version)).to match(/ruby/)
      expect(subject.extra).to eq({})
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.fingerprint).to eq([])
      expect(subject.transaction_names).to eq([])
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
      copy.fingerprint << "bar"

      expect(subject.breadcrumbs.to_hash).to eq({ values: [] })
      expect(subject.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version])
      expect(subject.contexts.dig(:runtime, :version)).to match(/ruby/)
      expect(subject.extra).to eq({})
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.fingerprint).to eq([])
      expect(subject.transaction_names).to eq([])
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
    before do
      subject.add_breadcrumb(new_breadcrumb)

      expect(subject.breadcrumbs.peek).to eq(new_breadcrumb)
    end

    it "clears all breadcrumbs by replacing the buffer object" do
      subject.clear_breadcrumbs

      expect(subject.breadcrumbs.empty?).to eq(true)
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

  describe "#clear" do
    subject do
      scope = described_class.new
      scope.set_tags({foo: "bar"})
      scope.set_extras({additional_info: "hello"})
      scope.set_user({id: 1})
      scope.set_transaction_name("WelcomeController#index")
      scope.set_fingerprint(["foo"])
      scope
    end

    it "resets the scope's data" do
      scope_id = subject.object_id

      subject.clear

      expect(subject.object_id).to eq(scope_id)
      expect(subject.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(subject.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version])
      expect(subject.contexts.dig(:runtime, :version)).to match(/ruby/)
      expect(subject.extra).to eq({})
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.fingerprint).to eq([])
      expect(subject.transaction_names).to eq([])
    end
  end

  describe "#apply_to_event" do
    let(:env) do
      Rack::MockRequest.env_for("/test", {})
    end

    before do
      Sentry.init do |config|
        config.dsn = DUMMY_DSN
      end
    end

    let(:client) do
      Sentry.get_current_client
    end

    subject do
      scope = described_class.new
      scope.set_tags({foo: "bar"})
      scope.set_extras({additional_info: "hello"})
      scope.set_user({id: 1})
      scope.set_transaction_name("WelcomeController#index")
      scope.set_fingerprint(["foo"])
      scope.set_rack_env(env)
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
      expect(event.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(event.fingerprint).to eq(["foo"])
      expect(event.contexts[:os].keys).to match_array([:name, :version, :build, :kernel_version])
      expect(event.contexts.dig(:runtime, :version)).to match(/ruby/)
      expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
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
      subject.add_event_processor do |event|
        event.tags = { processed: true }
        event
      end

      subject.apply_to_event(event)

      expect(event.tags).to eq({ processed: true })
    end

    it "sets trace context if there's a span" do
      span = Sentry::Span.new(op: "foo")
      subject.set_span(span)

      subject.apply_to_event(event)

      expect(event.contexts[:trace]).to eq(span.get_trace_context)
      expect(event.contexts.dig(:trace, :op)).to eq("foo")
    end
  end
end
