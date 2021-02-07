require "spec_helper"

RSpec.describe "Sentry::SendEventJob" do
  let(:event) do
    Sentry.get_current_client.event_from_message("test message")
  end
  let(:transport) do
    Sentry.get_current_client.transport
  end

  context "when ActiveJob is loaded" do
    require "active_job"

    after do
      Sentry.send(:remove_const, "SendEventJob")
      expect(defined?(Sentry::SendEventJob)).to eq(nil)
    end

    it "reports events to Sentry" do
      load File.join(Dir.pwd, "app", "jobs", "sentry", "send_event_job.rb")
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

    context "when ApplicationJob is not defined" do
      before do
        load File.join(Dir.pwd, "app", "jobs", "sentry", "send_event_job.rb")
        make_basic_app
      end
      it "uses ActiveJob::Base as the parent class" do
        expect(Sentry::SendEventJob.superclass).to eq(ActiveJob::Base)
      end
    end

    context "when ApplicationJob is defined" do
      before do
        class ApplicationJob < ActiveJob::Base; end
        load File.join(Dir.pwd, "app", "jobs", "sentry", "send_event_job.rb")
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
        load File.join(Dir.pwd, "app", "jobs", "sentry", "send_event_job.rb")
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
