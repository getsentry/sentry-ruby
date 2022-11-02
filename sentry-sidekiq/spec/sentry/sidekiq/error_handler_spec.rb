require 'spec_helper'

RSpec.describe Sentry::Sidekiq::ErrorHandler do
  before do
    perform_basic_setup
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

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

    event = transport.events.last.to_hash
    expect(Sentry::Event.get_message_from_exception(event)).to match("RuntimeError: Uhoh!")
    expect(event[:transaction]).to eq "Sidekiq/startup"
  end

  it "should capture exceptions based on Sidekiq context" do
    exception = build_exception

    subject.call(exception, context)

    expect(transport.events.count).to eq(1)
    event = transport.events.first.to_hash
    expect(event[:contexts][:sidekiq]).to eq(context)
  end

  it "filters out ActiveJob keys" do
    require "active_job"
    exception = build_exception
    aj_context = context
    aj_context["_aj_globalid"] = GlobalID.new('gid://app/model/id')
    expected_context = aj_context.dup
    expected_context.delete("_aj_globalid")
    expected_context["globalid"] = "gid://app/model/id"

    subject.call(exception, aj_context)

    expect(transport.events.count).to eq(1)
    event = transport.events.first.to_hash
    expect(event[:contexts][:sidekiq]).to eq(expected_context)
  end

  context "when the job is wrapped" do
    let(:context) { super().merge("class" => "WrapperJob", "wrapped" => "HardWorker") }

    it "should capture exceptions based on Sidekiq context" do
      exception = build_exception

      subject.call(exception, context)

      expect(transport.events.count).to eq(1)
      event = transport.events.first.to_hash
      expect(event[:transaction]).to eq("Sidekiq/HardWorker")
    end
  end
end
