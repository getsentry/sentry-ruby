# frozen_string_literal: true

require "spec_helper"

# Stub RubyLLM classes before loading the patch
module RubyLLM
  class Model
    attr_accessor :id, :provider

    def initialize(id:, provider:)
      @id = id
      @provider = provider
    end
  end

  class Message
    attr_accessor :model_id, :input_tokens, :output_tokens, :role, :content

    def initialize(role:, content:, model_id: nil, input_tokens: nil, output_tokens: nil)
      @role = role
      @content = content
      @model_id = model_id
      @input_tokens = input_tokens
      @output_tokens = output_tokens
    end
  end

  class ToolCall
    attr_accessor :name, :id, :arguments

    def initialize(name:, id:, arguments: nil)
      @name = name
      @id = id
      @arguments = arguments
    end
  end

  class Chat
    attr_reader :model, :messages

    def initialize(model:)
      @model = model
      @messages = []
    end

    def ask(message = nil, with: nil, &block)
      response = Message.new(
        role: :assistant,
        content: "Hello!",
        model_id: @model.id,
        input_tokens: 10,
        output_tokens: 20
      )
      @messages << response
      response
    end

    def execute_tool(tool_call)
      "tool_result"
    end
  end
end

# Load the patch after stubs are defined
require "sentry/ruby_llm"

RSpec.describe Sentry::RubyLLM do
  let(:model) { RubyLLM::Model.new(id: "gpt-4", provider: "openai") }
  let(:chat) { RubyLLM::Chat.new(model: model) }

  context "with tracing enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.enabled_patches << :ruby_llm
      end
    end

    it "records a span for ask" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      chat.ask("Hello")

      spans = transaction.span_recorder.spans
      ai_span = spans.find { |span| span.op == "gen_ai.chat" }

      expect(ai_span).not_to be_nil
      expect(ai_span.description).to eq("chat gpt-4")
      expect(ai_span.origin).to eq("auto.gen_ai.ruby_llm")
      expect(ai_span.data["gen_ai.operation.name"]).to eq("chat")
      expect(ai_span.data["gen_ai.request.model"]).to eq("gpt-4")
      expect(ai_span.data["gen_ai.system"]).to eq("openai")
    end

    it "records response data from the last message" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      chat.ask("Hello")

      spans = transaction.span_recorder.spans
      ai_span = spans.find { |span| span.op == "gen_ai.chat" }

      expect(ai_span.data["gen_ai.response.model"]).to eq("gpt-4")
      expect(ai_span.data["gen_ai.usage.input_tokens"]).to eq(10)
      expect(ai_span.data["gen_ai.usage.output_tokens"]).to eq(20)
    end

    it "records a span for execute_tool" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      tool_call = RubyLLM::ToolCall.new(name: "get_weather", id: "call_123", arguments: { location: "Tokyo" })
      chat.execute_tool(tool_call)

      spans = transaction.span_recorder.spans
      tool_span = spans.find { |span| span.op == "gen_ai.execute_tool" }

      expect(tool_span).not_to be_nil
      expect(tool_span.description).to eq("execute_tool get_weather")
      expect(tool_span.origin).to eq("auto.gen_ai.ruby_llm")
      expect(tool_span.data["gen_ai.operation.name"]).to eq("execute_tool")
      expect(tool_span.data["gen_ai.tool.name"]).to eq("get_weather")
      expect(tool_span.data["gen_ai.tool.call.id"]).to eq("call_123")
      expect(tool_span.data["gen_ai.tool.type"]).to eq("function")
    end

    context "when send_default_pii is true" do
      before { Sentry.configuration.send_default_pii = true }

      it "records tool arguments and result" do
        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        tool_call = RubyLLM::ToolCall.new(name: "get_weather", id: "call_123", arguments: { location: "Tokyo" })
        chat.execute_tool(tool_call)

        spans = transaction.span_recorder.spans
        tool_span = spans.find { |span| span.op == "gen_ai.execute_tool" }

        expect(tool_span.data["gen_ai.tool.call.arguments"]).to eq({ location: "Tokyo" }.to_json)
        expect(tool_span.data["gen_ai.tool.call.result"]).to eq("tool_result")
      end
    end

    context "when send_default_pii is false" do
      before { Sentry.configuration.send_default_pii = false }

      it "does not record tool arguments or result" do
        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        tool_call = RubyLLM::ToolCall.new(name: "get_weather", id: "call_123", arguments: { location: "Tokyo" })
        chat.execute_tool(tool_call)

        spans = transaction.span_recorder.spans
        tool_span = spans.find { |span| span.op == "gen_ai.execute_tool" }

        expect(tool_span.data).not_to have_key("gen_ai.tool.call.arguments")
        expect(tool_span.data).not_to have_key("gen_ai.tool.call.result")
      end
    end

    it "sets correct timestamps on span" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      chat.ask("Hello")

      spans = transaction.span_recorder.spans
      ai_span = spans.find { |span| span.op == "gen_ai.chat" }

      expect(ai_span.start_timestamp).not_to be_nil
      expect(ai_span.timestamp).not_to be_nil
      expect(ai_span.start_timestamp).to be < ai_span.timestamp
    end
  end

  context "with breadcrumb logger enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.enabled_patches << :ruby_llm
        config.breadcrumbs_logger << :ruby_llm_logger
      end
    end

    it "records a breadcrumb for ask" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      chat.ask("Hello")

      llm_breadcrumb = Sentry.get_current_scope.breadcrumbs.peek

      expect(llm_breadcrumb).not_to be_nil
      expect(llm_breadcrumb.data[:operation]).to eq("chat")
      expect(llm_breadcrumb.data[:name]).to eq("gpt-4")
      expect(llm_breadcrumb.data[:provider]).to eq("openai")
    end
  end

  context "without active transaction" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.enabled_patches << :ruby_llm
      end
    end

    it "does not create spans when no transaction is active" do
      result = chat.ask("Hello")
      expect(result).to be_a(RubyLLM::Message)
    end
  end

  context "when Sentry is not initialized" do
    it "does not interfere with normal operations" do
      # Create a fresh chat without Sentry initialized
      fresh_chat = RubyLLM::Chat.new(model: model)
      result = fresh_chat.ask("Hello")
      expect(result).to be_a(RubyLLM::Message)
    end
  end
end
