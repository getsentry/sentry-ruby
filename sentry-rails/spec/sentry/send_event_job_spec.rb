require "active_job"
require "spec_helper"

RSpec.describe "Sentry::SendEventJob" do
  let(:event) do
    Sentry.get_current_client.event_from_message("test message")
  end
  let(:transport) do
    Sentry.get_current_client.transport
  end

  context "when ActiveJob is not loaded" do
    before do
      TempActiveJob = ActiveJob
      Object.send(:remove_const, "ActiveJob")
      reload_send_event_job
    end

    after do
      ActiveJob = TempActiveJob
      reload_send_event_job
    end

    it "gets defined as a blank class" do
      expect(Sentry::SendEventJob.superclass).to eq(Object)
    end
  end

  context "when ActiveJob is loaded" do
    after do
      reload_send_event_job
    end

    it "reports events to Sentry" do
      make_basic_app

      Sentry.configuration.before_send = lambda do |event, hint|
        event.tags[:hint] = hint
        event
      end

      Sentry::SendEventJob.perform_now(event, { foo: "bar" })

      expect(transport.events.count).to eq(1)
      event = transport.events.first
      expect(event.message).to eq("test message")
      expect(event.tags[:hint][:foo]).to eq("bar")
    end

    it "doesn't create a new transaction" do
      make_basic_app do |config|
        config.traces_sample_rate = 1.0
      end

      Sentry::SendEventJob.perform_now(event)

      expect(transport.events.count).to eq(1)
      event = transport.events.first
      expect(event.type).to eq(nil)
    end

    context "when ApplicationJob is not defined" do
      before do
        make_basic_app
      end
      it "uses ActiveJob::Base as the parent class" do
        expect(Sentry::SendEventJob.superclass).to eq(ActiveJob::Base)
      end
    end

    context "when ApplicationJob is defined" do
      before do
        class ApplicationJob < ActiveJob::Base; end
        reload_send_event_job
        make_basic_app
      end

      after do
        Object.send(:remove_const, "ApplicationJob")
      end

      it "uses ApplicationJob as the parent class" do
        expect(Sentry::SendEventJob.superclass).to eq(ApplicationJob)
      end
    end

    context "when ApplicationJob is defined but it's something else" do
      before do
        class ApplicationJob; end
        reload_send_event_job
        make_basic_app
      end

      after do
        Object.send(:remove_const, "ApplicationJob")
      end

      it "uses ActiveJob::Base as the parent class" do
        expect(Sentry::SendEventJob.superclass).to eq(ActiveJob::Base)
      end
    end
  end
end
