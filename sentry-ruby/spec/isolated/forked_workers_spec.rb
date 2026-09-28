# frozen_string_literal: true

RSpec.describe Sentry::SessionFlusher, when: { ruby_engine?: "ruby" } do
  subject { Sentry.session_flusher }

  let(:session) do
    session = Sentry::Session.new
    session.close
    session
  end

  before do
    perform_basic_setup do |config|
      config.release = "test-release"
      config.environment = "test"
      config.background_worker_threads = 0
    end
  end

  after do
    subject.kill
    subject.thread&.join
  end

  it "discards aggregates inherited from the parent after a fork" do
    subject.add_session(session)

    result = capture_in_separate_process do |writer|
      subject.add_session(session)
      aggregate = subject.instance_variable_get(:@pending_aggregates).values.first
      writer.puts aggregate[:exited]
    end

    expect(result.to_i).to eq(1)
    expect(subject.instance_variable_get(:@pending_aggregates).values.first[:exited]).to eq(1)
  end
end

RSpec.shared_examples "forked telemetry buffer" do |event_factory:, max_items_config:|
  let(:event) { event_factory.call }

  before do
    perform_basic_setup do |config|
      config.background_worker_threads = 0
      config.public_send(:"#{max_items_config}=", 3)
    end
  end

  after do
    subject.kill
    subject.thread&.join
    Sentry.background_worker = Class.new { def shutdown; end }.new
  end

  it "resets inherited worker state before adding telemetry" do
    subject.add_item(event)
    subject.wait_until_idle
    expect(subject.size).to eq(1)

    result = capture_in_separate_process do |writer|
      subject.add_item(event)
      subject.flush
      item_count = sentry_envelopes.first.items.first.headers[:item_count]
      writer.puts [subject.size, sentry_envelopes.size, item_count].join(",")
    end

    child_size, child_envelopes, child_item_count = result.split(",").map(&:to_i)
    expect(child_size).to eq(0)
    expect(child_envelopes).to eq(1)
    expect(child_item_count).to eq(1)
    expect(subject.size).to eq(1)
    expect(sentry_envelopes).to be_empty

    subject.flush
    expect(sentry_envelopes.size).to eq(1)

    subject.add_item(event)
    subject.flush
    expect(sentry_envelopes.size).to eq(2)
  end
end

RSpec.describe Sentry::LogEventBuffer, when: { ruby_engine?: "ruby" } do
  subject { described_class.new(Sentry.configuration, Sentry.get_current_client) }

  include_examples "forked telemetry buffer",
    event_factory: -> { Sentry::LogEvent.new(level: :info, body: "Test message") },
    max_items_config: :max_log_events
end

RSpec.describe Sentry::MetricEventBuffer, when: { ruby_engine?: "ruby" } do
  subject { described_class.new(Sentry.configuration, Sentry.get_current_client) }

  include_examples "forked telemetry buffer",
    event_factory: -> { Sentry::MetricEvent.new(name: "test.metric", type: :counter, value: 1) },
    max_items_config: :max_metric_events
end
