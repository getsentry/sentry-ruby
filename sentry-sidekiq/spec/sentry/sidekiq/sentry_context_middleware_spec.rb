require "spec_helper"

RSpec.shared_context "sidekiq", shared_context: :metadata do
  let(:user) { { "id" => rand(10_000) } }

  let(:processor) do
    new_processor
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end
end

RSpec.describe Sentry::Sidekiq::SentryContextServerMiddleware do
  include_context "sidekiq"

  it "sets user to the event" do
    perform_basic_setup { |config| config.traces_sample_rate = 0 }
    Sentry.set_user(user)

    execute_worker(processor, SadWorker)

    expect(transport.events.count).to eq(1)
    event = transport.events[0]
    expect(event.user).to eq(user)
  end

  context "with tracing enabled" do
    before do
      perform_basic_setup { |config| config.traces_sample_rate = 1.0 }
      Sentry.set_user(user)
    end

    it "sets user to the transaction" do
      execute_worker(processor, HappyWorker)

      expect(transport.events.count).to eq(1)
      transaction = transport.events[0]
      expect(transaction).not_to be_nil
      expect(transaction.user).to eq(user)
    end

    it "sets user to both the event and transaction" do
      execute_worker(processor, SadWorker)

      expect(transport.events.count).to eq(2)
      transaction = transport.events[0]
      expect(transaction.user).to eq(user)
      event = transport.events.last
      expect(event.user).to eq(user)
    end

    it "sets sidekiq tags to the event" do
      execute_worker(processor, TagsWorker)
      event = transport.events.last
      expect(event.tags.keys).to include(:"sidekiq.marvel", :"sidekiq.dc")
    end

    context "with trace_propagation_headers" do
      let(:parent_transaction) { Sentry.start_transaction(op: "sidekiq") }

      it "starts the transaction from it" do
        trace_propagation_headers = { "sentry-trace" => parent_transaction.to_sentry_trace }
        execute_worker(processor, HappyWorker, trace_propagation_headers: trace_propagation_headers)

        expect(transport.events.count).to eq(1)
        transaction = transport.events[0]
        expect(transaction).not_to be_nil
        expect(transaction.contexts.dig(:trace, :trace_id)).to eq(parent_transaction.trace_id)
      end
    end
  end
end

RSpec.describe Sentry::Sidekiq::SentryContextClientMiddleware do
  include_context "sidekiq"

  let(:client) do
    Sidekiq::Client.new.tap do |client|
      client.middleware do |chain|
        chain.add described_class
      end
    end
  end

  # the default queue
  let!(:queue) { Sidekiq::Queue.new("default") }

  before do
    queue.clear
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
    end
  end

  it "does not add user to the job if they're absent in the current scope" do
    client.push('queue' => 'default', 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to be_nil
  end

  describe "with user" do
    before do
      Sentry.set_user(user)
    end

    it "sets user of the current scope to the job" do
      client.push('queue' => 'default', 'class' => HappyWorker, 'args' => [])

      expect(queue.size).to be(1)
      expect(queue.first["sentry_user"]).to eq(user)
    end
  end

  describe "with transaction" do
    let(:transaction) { Sentry.start_transaction(op: "sidekiq") }

    before do
      Sentry.get_current_scope.set_span(transaction)
    end

    it "sets the correct trace_propagation_headers linked to the transaction" do
      client.push('queue' => 'default', 'class' => HappyWorker, 'args' => [])

      expect(queue.size).to be(1)
      headers = queue.first["trace_propagation_headers"]
      expect(headers["sentry-trace"]).to eq(transaction.to_sentry_trace)
      expect(headers["baggage"]).to eq(transaction.to_baggage)
    end

    # sidekiq pushes the same job to the queue again from the server for schedules and retries
    it "keeps the same trace_propagation_headers linked to the transaction when queued multiple times" do
      client.push('queue' => 'default', 'class' => HappyWorker, 'args' => [])

      # push without span transaction to simulate pushing on the server
      Sentry.get_current_scope.clear
      client.push(queue.first.item)

      q = queue.to_a
      expect(q.size).to be(2)
      first_headers = q[0]["trace_propagation_headers"]
      expect(first_headers["sentry-trace"]).to eq(transaction.to_sentry_trace)
      expect(first_headers["baggage"]).to eq(transaction.to_baggage)

      second_headers = q[1]["trace_propagation_headers"]
      expect(second_headers["sentry-trace"]).to eq(transaction.to_sentry_trace)
      expect(second_headers["baggage"]).to eq(transaction.to_baggage)
    end
  end
end
