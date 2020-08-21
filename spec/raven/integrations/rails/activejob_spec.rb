require "spec_helper"

if defined? ActiveJob
  class MyActiveJob < ActiveJob::Base
    self.logger = nil

    class TestError < RuntimeError
    end

    def perform
      raise TestError, "Boom!"
    end
  end

  class RescuedActiveJob < MyActiveJob
    rescue_from TestError, :with => :rescue_callback

    def rescue_callback(error); end
  end
end

RSpec.describe "ActiveJob integration", :rails => true do
  before(:all) do
    require "rspec/rails"
    require "raven/integrations/rails"
    require "raven/integrations/rails/active_job"
  end

  before(:each) do
    Raven.client.transport.events = []
    MyActiveJob.queue_adapter = :inline
  end

  it_should_behave_like "Raven default capture behavior" do
    let(:block) { MyActiveJob.new.perform_now }
    let(:captured_class) { MyActiveJob::TestError }
    let(:captured_message) { "Boom!" }
  end

  it "clears context" do
    Raven.extra_context(:foo => :bar)
    job = MyActiveJob.new

    expect { job.perform_now }.to raise_error(MyActiveJob::TestError)
    event = JSON.parse!(Raven.client.transport.events.first[1])

    expect(event["extra"]["foo"]).to eq("bar")

    Raven.client.transport.events = []
    expect { job.perform_now }.to raise_error(MyActiveJob::TestError)
    event = JSON.parse!(Raven.client.transport.events.first[1])

    expect(event["extra"]["foo"]).to eq(nil)
  end

  context 'using rescue_from' do
    it 'does not trigger Sentry' do
      job = RescuedActiveJob.new
      allow(job).to receive(:rescue_callback)

      expect { job.perform_now }.not_to raise_error

      expect(Raven.client.transport.events.size).to eq(0)
      expect(job).to have_received(:rescue_callback).once
    end
  end

  context "when we are using an adapter which has a specific integration" do
    it "does not trigger sentry and re-raises" do
      MyActiveJob.queue_adapter = :sidekiq
      job = MyActiveJob.new

      expect { job.perform_now }.to raise_error(MyActiveJob::TestError)

      expect(Raven.client.transport.events.size).to eq(0)
    end
  end
end
