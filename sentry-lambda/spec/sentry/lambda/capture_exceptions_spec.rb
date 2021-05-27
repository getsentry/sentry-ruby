require 'spec_helper'
require 'sentry/lambda/capture_exceptions'
require 'sentry/lambda'

RSpec.describe Sentry::Lambda::CaptureExceptions do
  let(:exception) { ZeroDivisionError.new("divided by 0") }
  let(:additional_headers) { {} }
  let(:aws_event) do
    {}
  end
  let(:aws_context_remaining_time) { 0 }

  let(:aws_context) do
    OpenStruct.new(
      function_name: 'my-function',
      function_version: 'my-function-version',
      invoked_function_arn: 'my-function-arn',
      aws_request_id: 'my-aws-request-id',
      get_remaining_time_in_millis: aws_context_remaining_time
    )
  end
  let(:happy_response) do
    {
      statusCode: 200,
      body: {
        success: true,
        message: 'happy'
      }.to_json
    }
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  describe "exceptions capturing" do
    before do
      perform_basic_setup
    end

    it "allows for shorthand syntax" do
      response = Sentry::Lambda.wrap_handler(event: aws_event, context: aws_context) do
        happy_response
      end

      expect(response).to eq(happy_response)
    end

    it 'captures the exception from direct raise' do
       wrapped_handler = described_class.new(aws_event: aws_event, aws_context: aws_context)

      expect { wrapped_handler.call { raise exception } }.to raise_error(ZeroDivisionError)

      event = transport.events.last
      expect(event).to be_truthy
      # TODO: event does not have request - handle aws_event request data
      # expect(event.to_hash.dig(:request, :url)).to eq("http://example.org/test")
    end

    context 'considering remaining execution time' do
      # Simulates a 7 second function timeout
      # It ends up being a bit less than the configured timeout
      let(:aws_context_remaining_time) { 6875 }

      after do
        Timecop.return
      end

      it 'sets the transaction and captures extras' do
        now = Time.now
        Timecop.freeze(now)

         wrapped_handler = described_class.new(aws_event: aws_event, aws_context: aws_context)

         wrapped_handler.call do
          Timecop.freeze(now + 3)
          Sentry.capture_message('test')
          happy_response
        end

        event = transport.events.last
        expect(event.transaction).to eq("my-function")
        expect(event.extra.keys).to eq([:lambda, :'cloudwatch logs'])

        expect(event.extra[:lambda][:function_name]).to eq 'my-function'
        expect(event.extra[:lambda][:function_version]).to eq 'my-function-version'
        expect(event.extra[:lambda][:invoked_function_arn]).to eq 'my-function-arn'
        expect(event.extra[:lambda][:aws_request_id]).to eq 'my-aws-request-id'

        duration = event.extra.dig(:lambda, :execution_duration_in_millis)
        expect(duration).to eq 3000

        remaining_time = event.extra.dig(:lambda, :remaining_time_in_millis)
        expect(remaining_time).to eq (aws_context_remaining_time - duration)

        expect(event.extra[:'cloudwatch logs'].keys).to eq(%i[url log_group log_stream])
        expect(Sentry.get_current_scope.transaction_names).to be_empty
        expect(Sentry.get_current_scope.rack_env).to eq({})
      end
    end

    context 'capture_timeout_warning' do
      after do
        Timecop.return
      end

      let(:aws_context_remaining_time) { 1501 } #

      it 'captures a warning message' do
        now = Time.now
        Timecop.freeze(now)

         wrapped_handler = described_class.new(aws_event: aws_event, aws_context: aws_context, capture_timeout_warning: true)

         wrapped_handler.call do
          sleep 2

          happy_response
        end

        event = transport.events.last
        expect(event.message).to eq 'WARNING : Function is expected to get timed out. Configured timeout duration = 2 seconds.'
      end
    end

    context "handler does not return a hash response" do
      it 'does not raise an error' do
        expect { described_class.new(aws_event: aws_event, aws_context: aws_context).call {} }.not_to raise_error
      end
    end

    it 'returns happy result' do
       wrapped_handler = described_class.new(aws_event: aws_event, aws_context: aws_context)
      expect { wrapped_handler.call { happy_response } }.to_not raise_error
    end

    describe "state encapsulation" do
      before do
        Sentry.configure_scope { |s| s.set_tags(tag_1: "don't change me") }
      end

      it "only contains the breadcrumbs of the request" do
        logger = ::Logger.new(nil)

        logger.info("old breadcrumb")

        app_1 = described_class.new(aws_event: aws_event, aws_context: aws_context)

        app_1.call do
          logger.info("request breadcrumb")
          Sentry.capture_message("test")
          happy_response
        end

        event = transport.events.last
        expect(event.breadcrumbs.count).to eq(1)
        expect(event.breadcrumbs.peek.message).to eq("request breadcrumb")
      end
      it "doesn't pollute the top-level scope" do
        app_1 = described_class.new(aws_event: aws_event, aws_context: aws_context)

        app_1.call do
          Sentry.configure_scope { |s| s.set_tags({tag_1: "foo"}) }
          Sentry.capture_message("test")
          happy_response
        end

        event = transport.events.last
        expect(event.tags).to eq(tag_1: "foo")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
      end
      it "doesn't pollute other request's scope" do
        app_1 = described_class.new(aws_event: aws_event, aws_context: aws_context)
        app_1.call do
          Sentry.configure_scope { |s| s.set_tags({tag_1: "foo"}) }
          Sentry.capture_message('capture me')
          happy_response
        end

        event = transport.events.last
        expect(event.tags).to eq(tag_1: "foo")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")

        app_2 = described_class.new(aws_event: aws_event, aws_context: aws_context)

        app_2.call do
          Sentry.configure_scope { |s| s.set_tags({tag_2: "bar"}) }
          Sentry.capture_message('capture me 2')
          happy_response
        end

        event = transport.events.last
        expect(event.tags).to eq(tag_2: "bar", tag_1: "don't change me")
        expect(Sentry.get_current_scope.tags).to eq(tag_1: "don't change me")
      end
    end
  end

  describe "performance monitoring" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 0.5
      end
    end

    context "when the transaction is sampled" do
      before do
        allow(Random).to receive(:rand).and_return(0.4)
      end

      it "starts a span and finishes it" do
        described_class.new(aws_event: aws_event, aws_context: aws_context).call do
          happy_response
        end

        transaction = transport.events.last
        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
        expect(transaction.contexts.dig(:trace, :op)).to eq("serverless.function")
        expect(transaction.spans.count).to eq(0)
      end
    end

    context "when the transaction is not sampled" do
      before do
        allow(Random).to receive(:rand).and_return(0.6)
      end

      it "doesn't do anything" do
        described_class.new(aws_event: aws_event, aws_context: aws_context) do
          happy_response
        end

        expect(transport.events.count).to eq(0)
      end
    end

    context "when there's an exception" do
      before do
        allow(Random).to receive(:rand).and_return(0.4)
      end

      it "still finishes the transaction" do
        expect do
          described_class.new(aws_event: aws_event, aws_context: aws_context).call do
            raise 'foo'
          end
        end.to raise_error("foo")

        expect(transport.events.count).to eq(2)
        event = transport.events.first
        transaction = transport.events.last
        expect(event.contexts.dig(:trace, :trace_id).length).to eq(32)
        expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))


        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
        expect(transaction.contexts.dig(:trace, :op)).to eq("serverless.function")
        expect(transaction.spans.count).to eq(0)
      end
    end

    context 'when there is as sentry error' do
      before do
        allow(Random).to receive(:rand).and_return(0.4)
      end

      it "still finishes the transaction" do
        expect do
          described_class.new(aws_event: aws_event, aws_context: aws_context).call do
            raise Sentry::Error, 'foo'
          end
        end.to raise_error("foo")

        expect(transport.events.count).to eq(1)
        event = transport.events.first
        transaction = transport.events.last
        expect(event.contexts.dig(:trace, :trace_id).length).to eq(32)
        expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))


        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
        expect(transaction.contexts.dig(:trace, :op)).to eq("serverless.function")
        expect(transaction.spans.count).to eq(0)
      end
    end

    context "when traces_sample_rate is not set" do
      before do
        Sentry.configuration.traces_sample_rate = nil
      end

      it "doesn't record transaction" do
        described_class.new(aws_event: aws_event, aws_context: aws_context) { happy_response }

        expect(transport.events.count).to eq(0)
      end

      context "when sentry-trace header is sent" do
        let(:external_transaction) do
          Sentry::Transaction.new(
            op: "pageload",
            status: "ok",
            sampled: true,
            name: "a/path",
            hub: Sentry.get_current_hub
          )
        end

        let(:aws_event) { { 'HTTP_SENTRY_TRACE' => external_transaction.to_sentry_trace } }

        it "doesn't cause the transaction to be recorded" do
          response = described_class.new(aws_event: aws_event, aws_context: aws_context).call { happy_response }

          expect(response[:statusCode]).to eq(200)
          expect(transport.events).to be_empty
        end
      end
    end
  end
end
