# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob::JobMonitor do
  before do
    perform_basic_setup
  end

  let(:job_class) { Class.new(ActiveJob::Base) }

  describe ".setup_for_job_class" do
    context "when Rails is not available" do
      before do
        hide_const("Rails")
      end

      it "does not set up monitoring" do
        expect(job_class).not_to receive(:include)
        described_class.setup_for_job_class(job_class)
      end
    end

    context "when Sentry is not initialized" do
      before do
        stub_const("Rails", double("Rails"))
        allow(Sentry).to receive(:initialized?).and_return(false)
      end

      it "does not set up monitoring" do
        expect(job_class).not_to receive(:include)
        described_class.setup_for_job_class(job_class)
      end
    end

    context "when Rails and Sentry are available" do
      before do
        stub_const("Rails", double("Rails"))
        allow(Sentry).to receive(:initialized?).and_return(true)
      end

      it "includes Sentry::Cron::MonitorCheckIns" do
        expect(job_class).to receive(:include).with(Sentry::Cron::MonitorCheckIns)
        described_class.setup_for_job_class(job_class)
      end

      it "adds _sentry attribute accessor" do
        expect(job_class).to receive(:attr_accessor).with(:_sentry)
        described_class.setup_for_job_class(job_class)
      end

      it "sets up around_enqueue hook" do
        expect(job_class).to receive(:around_enqueue)
        described_class.setup_for_job_class(job_class)
      end

      it "sets up around_perform hook" do
        expect(job_class).to receive(:around_perform)
        described_class.setup_for_job_class(job_class)
      end

      it "adds sentry_cron_monitor class method" do
        described_class.setup_for_job_class(job_class)
        expect(job_class).to respond_to(:sentry_cron_monitor)
      end

      it "adds enqueue instance method" do
        described_class.setup_for_job_class(job_class)
        expect(job_class.instance_methods).to include(:enqueue)
      end

      it "adds serialize instance method" do
        described_class.setup_for_job_class(job_class)
        expect(job_class.instance_methods).to include(:serialize)
      end

      it "adds deserialize instance method" do
        described_class.setup_for_job_class(job_class)
        expect(job_class.instance_methods).to include(:deserialize)
      end

      it "adds private helper methods" do
        described_class.setup_for_job_class(job_class)
        expect(job_class.private_instance_methods).to include(:_sentry_set_span_data)
        expect(job_class.private_instance_methods).to include(:_sentry_job_context)
        expect(job_class.private_instance_methods).to include(:_sentry_start_transaction)
        expect(job_class.private_instance_methods).to include(:_sentry_finish_transaction)
      end

      it "makes helper methods private" do
        expect(job_class).to receive(:class_eval).at_least(:once)
        described_class.setup_for_job_class(job_class)
      end

      context "when job class already has Sentry::Cron::MonitorCheckIns included" do
        before do
          job_class.include(Sentry::Cron::MonitorCheckIns)
        end

        it "does not include it again" do
          expect(job_class).not_to receive(:include).with(Sentry::Cron::MonitorCheckIns)
          described_class.setup_for_job_class(job_class)
        end
      end

      context "when hooks are already set up" do
        before do
          job_class.define_singleton_method(:sentry_enqueue_hook_setup) { true }
          job_class.define_singleton_method(:sentry_perform_hook_setup) { true }
        end

        it "does not set up hooks again" do
          expect(job_class).not_to receive(:around_enqueue)
          expect(job_class).not_to receive(:around_perform)
          described_class.setup_for_job_class(job_class)
        end
      end
    end
  end
end
