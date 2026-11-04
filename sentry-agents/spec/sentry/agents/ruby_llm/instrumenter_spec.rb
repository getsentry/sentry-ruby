# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Sentry::Agents::RubyLLM::Instrumenter do
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

  it "installs idempotently during Sentry initialization" do
    instrumenter = RubyLLM.config.instrumenter

    expect(instrumenter).to be_a(described_class)
  end

  it "installs on an isolated RubyLLM context" do
    context = RubyLLM.context
    context.config.instrumenter = nil

    Sentry::Agents::RubyLLM.install(context.config)

    expect(context.config.instrumenter).to be_a(described_class)
  end

  it "creates a standalone chat transaction and serializes content" do
    response = message(role: :assistant, content: "Paris", model: "gpt-4o", finish_reason: :stop)
    payload = chat_payload

    result = instrument(described_class.new, "chat.ruby_llm", payload) do |event|
      event[:response] = response
      "result"
    end

    expect(result).to eq("result")

    event = transaction_event
    data = model_data(event)
    expect(event.transaction).to eq("chat gpt-4o")
    expect(model_op(event)).to eq("gen_ai.chat")
    expect(model_description(event)).to eq("chat gpt-4o")
    expect(data["gen_ai.operation.name"]).to eq("chat")
    expect(data["gen_ai.provider.name"]).to eq("openai")
    expect(data["gen_ai.request.model"]).to eq("gpt-4o")
    expect(data["gen_ai.request.temperature"]).to eq(0.2)
    expect(data["gen_ai.request.max_tokens"]).to eq(20)
    expect(JSON.parse(data["gen_ai.input.messages"])).to eq(
      [{ "role" => "user", "parts" => [{ "type" => "text", "content" => "hello" }] }]
    )
    expect(JSON.parse(data["gen_ai.system_instructions"])).to eq(
      [{ "type" => "text", "content" => "Be concise" }]
    )
    expect(JSON.parse(data["gen_ai.output.messages"])).to eq(
      [{ "role" => "assistant", "parts" => [{ "type" => "text", "content" => "Paris" }] }]
    )
    expect(data["gen_ai.response.model"]).to eq("gpt-4o")
    expect(data["gen_ai.response.finish_reasons"]).to eq(["stop"])
  end

  it "records semantic provider, streaming, and reasoning attributes" do
    payload = chat_payload(
      provider: "bedrock",
      streaming: true,
      thinking: RubyLLM::Thinking::Config.new(effort: :high)
    )

    instrument(described_class.new, "chat.ruby_llm", payload) { |event| event[:response] = message }

    data = model_data(transaction_event)
    expect(data["gen_ai.provider.name"]).to eq("aws.bedrock")
    expect(data["gen_ai.request.stream"]).to be(true)
    expect(data["gen_ai.request.reasoning.level"]).to eq("high")
  end

  it "keeps model spans as children of an existing transaction and restores scope" do
    parent = Sentry.start_transaction(name: "parent", op: "test")
    Sentry.get_current_scope.set_span(parent)

    instrument(described_class.new, "chat.ruby_llm", chat_payload) { :result }

    expect(Sentry.get_current_scope.get_span).to eq(parent)
    parent.finish

    event = transaction_event
    expect(event.transaction).to eq("parent")
    expect(event.spans.size).to eq(1)
    expect(event.spans.first[:op]).to eq("gen_ai.chat")
  end

  it "records usage attempts without using response tokens" do
    response = message(role: :assistant, content: "done", tokens: RubyLLM::Tokens.new(input: 999, output: 999))
    adapter = described_class.new

    instrument(adapter, "chat.ruby_llm", chat_payload) do |event|
      instrument(adapter, "usage.ruby_llm", tokens: RubyLLM::Tokens.new(input: 10, output: 4, cache_read: 2, cache_write: 3, thinking: 1))
      instrument(adapter, "usage.ruby_llm", tokens: RubyLLM::Tokens.new(input: 0, output: 2, cache_read: 0, cache_write: 0, thinking: 0))
      event[:response] = response
    end

    data = model_data(transaction_event)
    expect(data["gen_ai.usage.input_tokens"]).to eq(15)
    expect(data["gen_ai.usage.output_tokens"]).to eq(6)
    expect(data["gen_ai.usage.cache_read.input_tokens"]).to eq(2)
    expect(data["gen_ai.usage.cache_creation.input_tokens"]).to eq(3)
    expect(data["gen_ai.usage.reasoning.output_tokens"]).to eq(1)
  end

  it "gates input and output content independently" do
    Sentry.configuration.data_collection.gen_ai.inputs = false
    Sentry.configuration.data_collection.gen_ai.outputs = false
    response = message(role: :assistant, content: "secret")

    instrument(described_class.new, "chat.ruby_llm", chat_payload) do |event|
      event[:response] = response
    end

    data = model_data(transaction_event)
    expect(data).not_to have_key("gen_ai.input.messages")
    expect(data).not_to have_key("gen_ai.system_instructions")
    expect(data).not_to have_key("gen_ai.output.messages")
    expect(data["gen_ai.request.model"]).to eq("gpt-4o")
  end

  it "passes through uninstrumented events and application exceptions" do
    adapter = described_class.new

    expect(instrument(adapter, "request.ruby_llm", {}) { :result }).to eq(:result)

    expect do
      instrument(adapter, "chat.ruby_llm", chat_payload) { raise "boom" }
    end.to raise_error(RuntimeError, "boom")

    expect(transaction_event.transaction).to eq("chat gpt-4o")
  end

  def instrument(adapter, name, payload, &block)
    return adapter.instrument(name, payload) unless block

    adapter.instrument(name, payload) { block.call(payload) }
  end

  def model_data(event)
    event.spans.first&.fetch(:data) || event.contexts[:trace][:data]
  end

  def model_op(event)
    event.spans.first&.fetch(:op) || event.contexts[:trace][:op]
  end

  def model_description(event)
    event.spans.first&.fetch(:description) || event.transaction
  end

  def transaction_event
    Sentry.get_current_client.flush
    sentry_events.find { |event| event.is_a?(Sentry::TransactionEvent) }
  end

  def chat_payload(provider: "openai", streaming: false, thinking: nil)
    {
      chat: Struct.new(:tools).new({}),
      provider_tools: [],
      provider: provider,
      model: "gpt-4o",
      input_messages: [
        message(role: :system, content: "Be concise"),
        message(role: :user, content: "hello")
      ],
      temperature: 0.2,
      max_output_tokens: 20,
      streaming: streaming,
      thinking: thinking
    }
  end

  def message(**attributes)
    RubyLLM::Message.new({ role: :user, content: "message" }.merge(attributes))
  end
end
