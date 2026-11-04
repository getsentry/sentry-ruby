# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Agents::RubyLLM::AgentRuns do
  before do
    RubyLLM.config.instrumenter = nil
    RubyLLM.configure { |config| config.openai_api_key = "test" }
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

  it "creates one invoke_agent span with model and tool descendants" do
    agent_class = agent_class("SupportAgent")
    chat = agent_class.chat
    adapter = Sentry::Agents::RubyLLM::Instrumenter.new(nil)

    result = described_class.with(chat) do
      adapter.instrument("chat.ruby_llm", chat_payload(chat)) { :model_result }
      adapter.instrument("tool_call.ruby_llm", tool_payload(chat)) { :tool_result }
      :agent_result
    end

    expect(result).to eq(:agent_result)
    event = transaction_event
    root_trace = event.contexts[:trace]
    spans = event.spans

    expect(root_trace[:op]).to eq("gen_ai.invoke_agent")
    expect(root_trace[:data]["gen_ai.agent.name"]).to eq("SupportAgent")
    expect(spans.map { |span| span[:op] }).to contain_exactly("gen_ai.chat", "gen_ai.execute_tool")
    expect(spans.map { |span| span[:data]["gen_ai.agent.name"] }).to all(eq("SupportAgent"))
    expect(spans.map { |span| span[:parent_span_id] }).to all(eq(root_trace[:span_id]))
  end

  it "suppresses duplicate wrappers for the same chat and keeps nested agents" do
    outer_class = agent_class("OuterAgent")
    inner_class = agent_class("InnerAgent")
    outer_chat = outer_class.chat
    inner_chat = inner_class.chat

    described_class.with(outer_chat) do
      described_class.with(outer_chat) { :same_chat }
      described_class.with(inner_chat) { :nested_chat }
    end

    event = transaction_event
    root_trace = event.contexts[:trace]
    invoke_spans = event.spans.select { |span| span[:op] == "gen_ai.invoke_agent" }

    expect(invoke_spans.size).to eq(1)
    expect(invoke_spans.first[:data]["gen_ai.agent.name"]).to eq("InnerAgent")
    expect(invoke_spans.first[:parent_span_id]).to eq(root_trace[:span_id])
  end

  it "finishes the invoke_agent span when the operation raises" do
    chat = agent_class("FailingAgent").chat

    expect do
      described_class.with(chat) { raise "agent failure" }
    end.to raise_error(RuntimeError, "agent failure")

    event = transaction_event
    trace = event.contexts[:trace]
    expect(trace[:status]).to eq("internal_error")
    expect(trace[:data]["error.type"]).to eq("RuntimeError")
  end

  def agent_class(name)
    stub_const(name, Class.new(RubyLLM::Agent)).tap do |klass|
      klass.model "gpt-4o"
    end
  end

  def chat_payload(chat)
    {
      chat: chat,
      provider: "openai",
      model: "gpt-4o",
      input_messages: []
    }
  end

  def tool_payload(chat)
    {
      chat: chat,
      tool_name: "weather",
      tool_arguments: { city: "Paris" }
    }
  end

  def transaction_event
    Sentry.get_current_client.flush
    sentry_events.find { |event| event.is_a?(Sentry::TransactionEvent) }
  end
end
