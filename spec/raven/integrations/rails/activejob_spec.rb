require "spec_helper"

if defined? ActiveJob
  class MyActiveJob < ActiveJob::Base
    self.queue_adapter = :inline
    self.logger = nil

    class TestError < RuntimeError
    end

    def perform
      raise TestError, "Boom!"
    end
  end
end

describe "ActiveJob integration", :rails => true do
  before(:all) do
    require "rspec/rails"
    require "raven/integrations/rails"
    require "raven/integrations/rails/active_job"
  end

  before(:each) do
    Raven.client.transport.events = []
  end

  it "captures exceptions" do
    job = MyActiveJob.new

    expect { job.perform_now }.to raise_error(MyActiveJob::TestError)

    expect(Raven.client.transport.events.size).to eq(1)
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
end
