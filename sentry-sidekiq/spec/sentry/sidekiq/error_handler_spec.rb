# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Sidekiq::ErrorHandler do
  before do
    perform_basic_setup
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  if WITH_SIDEKIQ_8
    let(:context) do
      {
        "args" => [true, true],
        "class" => "HardWorker",
        "created_at" => 1_474_922_824_910,
        "enqueued_at" => 1_474_922_824_910,
        "error_class" => "RuntimeError",
        "error_message" => "a wild exception appeared",
        "failed_at" => 1_474_922_825_158,
        "jid" => "701ed9cfa51c84a763d56bc4",
        "queue" => "default",
        "retry" => true,
        "retry_count" => 0
      }
    end
  else
    let(:context) do
      {
        "args" => [true, true],
        "class" => "HardWorker",
        "created_at" => 1_474_922_824.910579,
        "enqueued_at" => 1_474_922_824.910665,
        "error_class" => "RuntimeError",
        "error_message" => "a wild exception appeared",
        "failed_at" => 1_474_922_825.158953,
        "jid" => "701ed9cfa51c84a763d56bc4",
        "queue" => "default",
        "retry" => true,
        "retry_count" => 0
      }
    end
  end

  let(:processor) do
    new_processor
  end

  it "captures exceptions raised during events" do
    if WITH_SIDEKIQ_7
      config = Sidekiq.instance_variable_get(:@config)
      config[:lifecycle_events][:startup] = [proc { raise "Uhoh!" }]
      Sidekiq::Embedded.new(config).fire_event(:startup)
    else
      Sidekiq.options[:lifecycle_events][:startup] = [proc { raise "Uhoh!" }]
      processor.fire_event(:startup)
    end

    event = transport.events.last.to_h
    expect(event[:exception][:values][0][:type]).to eq("RuntimeError")
    expect(event[:exception][:values][0][:value]).to match("Uhoh!")
    expect(event[:transaction]).to eq "Sidekiq/startup"
  end

  it "should capture exceptions based on Sidekiq context" do
    exception = build_exception

    subject.call(exception, context)

    expect(transport.events.count).to eq(1)
    event = transport.events.first.to_h
    expect(event[:contexts][:sidekiq]).to eq(context)
  end

  it "filters out ActiveJob keys from an ActiveJob job" do
    require "active_job"
    exception = build_exception
    aj_job = context.merge("wrapped" => "HardJob", "_aj_globalid" => GlobalID.new('gid://app/model/id'))
    expected_context = aj_job.reject { |key, _value| key == "_aj_globalid" }.merge(context: "Job raised exception", "globalid" => "gid://app/model/id")

    subject.call(exception, { context: "Job raised exception", job: aj_job })

    expect(transport.events.count).to eq(1)
    event = transport.events.first.to_h
    expect(event[:contexts][:sidekiq]).to eq(expected_context)
    expect(event[:transaction]).to eq("Sidekiq/HardJob")
  end

  context "when the extension handling the job raises" do
    let(:failing_extension_class) do
      Class.new(Sentry::Sidekiq::JobExtension) do
        define_method(:error_data) { |**| raise "extension failure" }
        define_method(:integration) { |**| raise "extension failure" }
      end
    end

    subject { described_class.new(failing_extension_class.new(name: :failing)) }

    it "still captures the exception with the Sidekiq context" do
      exception = build_exception

      subject.call(exception, { context: "Job raised exception", job: context })

      expect(transport.events.count).to eq(1)
      expect(transport.events.first.contexts[:sidekiq]).to include("jid" => context["jid"], "class" => "HardWorker")
    end
  end

  context "when the job is wrapped" do
    let(:context) { super().merge("class" => "WrapperJob", "wrapped" => "HardWorker") }

    it "should capture exceptions based on Sidekiq context" do
      exception = build_exception

      subject.call(exception, context)

      expect(transport.events.count).to eq(1)
      event = transport.events.first.to_h
      expect(event[:transaction]).to eq("Sidekiq/HardWorker")
    end
  end
end
