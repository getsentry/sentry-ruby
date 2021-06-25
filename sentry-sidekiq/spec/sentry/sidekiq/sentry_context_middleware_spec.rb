require "spec_helper"

RSpec.shared_context "sidekiq", shared_context: :metadata do
  let(:user) { { "id" => rand(10_000) } }

  let(:processor) do
    options = { queues: ['default'] }
    Sidekiq::Manager.new(options).workers.first
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

    process_job(processor, "SadWorker")

    expect(transport.events.count).to eq(1)
    event = transport.events.first
    expect(event.user).to eq(user)
  end

  context "with tracing enabled" do
    before do
      perform_basic_setup { |config| config.traces_sample_rate = 1.0 }
      Sentry.set_user(user)
    end

    it "sets user to the transaction" do
      process_job(processor, "HappyWorker")

      expect(transport.events.count).to eq(1)
      transaction = transport.events.first
      expect(transaction).not_to be_nil
      expect(transaction.user).to eq(user)
    end

    it "sets user to both the event and transaction" do
      process_job(processor, "SadWorker")

      expect(transport.events.count).to eq(2)
      transaction = transport.events.first
      expect(transaction.user).to eq(user)
      event = transport.events.last
      expect(event.user).to eq(user)
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
    perform_basic_setup
  end

  it "does not add user to the job if user is absence in the current scope" do
    client.push('queue' => 'default', 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to be_nil
  end

  it "sets user of the current scope to the job if present" do
    Sentry.set_user(user)

    client.push('queue' => 'default', 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to eq(user)
  end
end
