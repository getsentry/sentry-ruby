require "spec_helper"

RSpec.shared_context "sidekiq", shared_context: :metadata do
  let(:user) { { "id" => rand(10_000) } }

  let(:client) do
    Sidekiq::Client.new.tap do |client|
      client.middleware do |chain|
        chain.add Sentry::Sidekiq::SentryContextClientMiddleware
      end
    end
  end

  let(:random_empty_queue) do
    Sidekiq::Queue.new(rand(10_000)).tap do |queue|
      queue.clear
    end
  end
end

RSpec.describe Sentry::Sidekiq::SentryContextServerMiddleware do
  include_context "sidekiq"

  after { Sidekiq::RetrySet.new.clear }

  it "sets user from the job to events" do
    perform_basic_setup { |config| config.traces_sample_rate = 1.0 }
    Sentry.set_user(user)

    queue = random_empty_queue
    options = { queues: [queue.name] }
    processor = Sidekiq::Manager.new(options).workers.first

    client.push('queue' => queue.name, 'class' => HappyWorker, 'args' => [])

    expect { processor.send(:process_one) }.
      to change { Sentry.get_current_client.transport.events.size }.by(1)

    event =  Sentry.get_current_client.transport.events.first
    expect(event).not_to be_nil
    expect(event.user).to eq(user)
  end

  it "sets user from the job to sidekiq event if worker raises an exception" do
    perform_basic_setup { |config| config.traces_sample_rate = 0 }
    Sentry.set_user(user)

    queue = random_empty_queue
    options = { queues: [queue.name] }
    processor = Sidekiq::Manager.new(options).workers.first

    client.push('queue' => queue.name, 'class' => SadWorker, 'args' => [])

    expect do
      begin; processor.send(:process_one); rescue RuntimeError; end
    end.
      to change { Sentry.get_current_client.transport.events.size }.by(1)

    Sentry.get_current_client.transport.events.each do |event|
      expect(event.user).to eq(user)
    end
  end

  it "sets user from the job to sidekiq and error events if worker raises an exception when trace enabled" do
    perform_basic_setup { |config| config.traces_sample_rate = 1.0 }
    Sentry.set_user(user)

    queue = random_empty_queue
    options = { queues: [queue.name] }
    processor = Sidekiq::Manager.new(options).workers.first

    client.push('queue' => queue.name, 'class' => SadWorker, 'args' => [])

    # XXX: In ruby 2.4, two events are pushed. In other versions, only one
    # event is pushed. Use by_at_least.
    expect do
      begin; processor.send(:process_one); rescue RuntimeError; end
    end.
      to change { Sentry.get_current_client.transport.events.size }.by_at_least(1)

    Sentry.get_current_client.transport.events.each do |event|
      expect(event.user).to eq(user)
    end
  end
end

RSpec.describe Sentry::Sidekiq::SentryContextClientMiddleware do
  include_context "sidekiq"

  before { perform_basic_setup }

  it "does not user to the job if user is absence in the current scope" do
    queue = random_empty_queue
    client.push('queue' => queue.name, 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to be_nil
  end

  it "sets user of the current scope to the job if present" do
    queue = random_empty_queue
    Sentry.set_user(user)

    client.push('queue' => queue.name, 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to eq(user)
  end
end
