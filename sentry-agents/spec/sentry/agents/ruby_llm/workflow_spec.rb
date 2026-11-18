# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RubyLLM workflows" do
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

  it "groups workflows and steps and propagates the pipeline name" do
    result = RubyLLM.workflow("Research") do |workflow|
      workflow.step("Draft") do
        RubyLLM::Support::Instrumentation.instrument(
          "chat.ruby_llm",
          provider: "openai",
          model: "gpt-4o"
        ) do |event|
          event[:response] = RubyLLM::Message.new(role: :assistant, content: "done", model: "gpt-4o")
          :chat_result
        end
      end
    end

    expect(result).to eq(:chat_result)
    Sentry.get_current_client.flush
    event = sentry_events.find { |item| item.is_a?(Sentry::TransactionEvent) }
    root_trace = event.contexts[:trace]
    step = event.spans.find { |span| span[:op] == "ai.run" }
    chat = event.spans.find { |span| span[:op] == "gen_ai.chat" }

    expect(event.transaction).to eq("Research")
    expect(root_trace[:op]).to eq("ai.pipeline")
    expect(root_trace[:data]["gen_ai.pipeline.name"]).to eq("Research")
    expect(step[:description]).to eq("Draft")
    expect(step[:parent_span_id]).to eq(root_trace[:span_id])
    expect(step[:data]["gen_ai.pipeline.name"]).to eq("Research")
    expect(chat[:parent_span_id]).to eq(step[:span_id])
    expect(chat[:data]["gen_ai.pipeline.name"]).to eq("Research")
  end
end
