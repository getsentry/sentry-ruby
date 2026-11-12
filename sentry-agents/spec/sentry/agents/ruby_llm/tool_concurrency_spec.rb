# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Agents::RubyLLM::ToolConcurrency do
  before do
    RubyLLM.config.instrumenter = nil
    Sentry.init do |config|
      config.dsn = Sentry::TestHelper::DUMMY_DSN
      config.sdk_logger = Logger.new(nil)
      config.background_worker_threads = 0
      config.transport.transport_class = Sentry::DummyTransport
      config.traces_sample_rate = 1.0
      config.data_collection.gen_ai.inputs = true
      config.data_collection.gen_ai.outputs = true
    end
  end

  after do
    RubyLLM.config.instrumenter = nil
  end

  it "propagates an isolated hub while retaining the parent span recorder" do
    parent = Sentry.start_transaction(name: "parent", op: "test")
    Sentry.get_current_scope.set_span(parent)
    adapter = Sentry::Agents::RubyLLM::Instrumenter.new(nil)
    seen_spans = Queue.new

    results = RubyLLM::Chat::ToolConcurrency.run(:threads, { first: "first", second: "second" }) do |tool_call|
      adapter.instrument("tool_call.ruby_llm", tool_name: tool_call, tool_arguments: {}) do |event|
        seen_spans << Sentry.get_current_scope.get_span
        event[:result] = tool_call
        tool_call
      end
    end

    expect(results.map(&:last)).to contain_exactly("first", "second")
    expect(seen_spans.size).to eq(2)
    expect(seen_spans.size.times.map { seen_spans.pop.parent_span_id }).to all(eq(parent.span_id))
    expect(Sentry.get_current_scope.get_span).to eq(parent)

    parent.finish
    event = sentry_events.find { |item| item.is_a?(Sentry::TransactionEvent) }
    expect(event.spans.size).to eq(2)
    expect(event.spans.map { |span| span[:op] }).to all(eq("gen_ai.execute_tool"))
  end
end
