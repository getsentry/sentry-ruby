require "spec_helper"
require "active_job/railtie"

class FailedJob < ActiveJob::Base
  self.logger = nil

  class TestError < RuntimeError
  end

  def perform
    raise TestError, "Boom!"
  end
end

class MyActiveJob < FailedJob
  def perform
    Sentry.get_current_scope.set_extras(foo: :bar)
    super
  end
end

class RescuedActiveJob < MyActiveJob
  rescue_from TestError, :with => :rescue_callback

  def rescue_callback(error); end
end

RSpec.describe "without Sentry initialized" do
  before(:each) do
    FailedJob.queue_adapter = :inline
  end

  it "runs job" do
    job = FailedJob.new

    expect { job.perform_now }.to raise_error(FailedJob::TestError)
  end
end

RSpec.describe "ActiveJob integration" do
  before(:all) do
    make_basic_app
  end

  let(:event) do
    transport.events.last.to_json_compatible
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  after do
    transport.events = []
  end

  before(:each) do
    MyActiveJob.queue_adapter = :inline
  end

  it "clears context" do
    job = MyActiveJob.new

    expect { job.perform_now }.to raise_error(MyActiveJob::TestError)

    event = transport.events.last.to_json_compatible

    expect(event["extra"]["foo"]).to eq("bar")

    expect(Sentry.get_current_scope.extra).to eq({})
  end

  context 'using rescue_from' do
    it 'does not trigger Sentry' do
      job = RescuedActiveJob.new
      allow(job).to receive(:rescue_callback)

      expect { job.perform_now }.not_to raise_error

      expect(transport.events.size).to eq(0)
      expect(job).to have_received(:rescue_callback).once
    end
  end

  context "when we are using an adapter which has a specific integration" do
    it "does not trigger sentry and re-raises" do
      MyActiveJob.queue_adapter = :sidekiq
      job = MyActiveJob.new

      expect { job.perform_now }.to raise_error(MyActiveJob::TestError)

      expect(transport.events.size).to eq(0)
    end
  end
end
