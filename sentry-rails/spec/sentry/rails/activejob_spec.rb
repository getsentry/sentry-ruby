require "spec_helper"

class MyActiveJob < ActiveJob::Base
  self.logger = nil

  class TestError < RuntimeError
  end

  def perform
    Sentry.get_current_scope.set_extras(foo: :bar)
    raise TestError, "Boom!"
  end
end

class RescuedActiveJob < MyActiveJob
  rescue_from TestError, :with => :rescue_callback

  def rescue_callback(error); end
end

RSpec.describe "ActiveJob integration" do
  before(:all) do
    perform_basic_setup
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

  context "when DeserializationError happens in user's jobs" do
    before do
      make_basic_app
    end

    class DeserializationErrorJob < ActiveJob::Base
      def perform
        1/0
      rescue
        raise ActiveJob::DeserializationError
      end
    end

    it "reports the root cause to Sentry" do
      expect do
        DeserializationErrorJob.perform_now
      end.to raise_error(ActiveJob::DeserializationError, /divided by 0/)

      expect(transport.events.size).to eq(1)

      event = transport.events.last.to_json_compatible
      expect(event.dig("exception", "values", 0, "type")).to eq("ZeroDivisionError")
    end

    context "and in user-defined reporting job too" do
      before do
        Sentry.configuration.async = lambda do |event, hint|
          UserDefinedReportingJob.perform_now(event, hint)
        end
      end

      class UserDefinedReportingJob < ActiveJob::Base
        def perform(event, hint)
          Post.find(0)
        rescue
          raise ActiveJob::DeserializationError
        end
      end

      it "doesn't cause infinite loop because of excluded exceptions" do
        expect do
          DeserializationErrorJob.perform_now
        end.to raise_error(ActiveJob::DeserializationError, /divided by 0/)
      end
    end

    context "and in customized SentryJob too" do
      before do
        class CustomSentryJob < ::Sentry::SendEventJob
          def perform(event)
            raise "Not excluded exception"
          rescue
            raise ActiveJob::DeserializationError
          end
        end

        Sentry.configuration.async = lambda do |event, hint|
          CustomSentryJob.perform_now(event, hint)
        end
      end

      it "doesn't cause infinite loop" do
        expect do
          DeserializationErrorJob.perform_now
        end.to raise_error(ActiveJob::DeserializationError, /divided by 0/)
      end
    end
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
