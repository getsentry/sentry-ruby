require 'spec_helper'
require 'raven/integrations/sidekiq'

describe Raven::SidekiqErrorHandler do
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

  it "should capture exceptions based on Sidekiq context" do
    exception = build_exception
    expected_options = {
      :message => exception.message,
      :extra => { :sidekiq => context },
      :culprit => "Sidekiq/HardWorker"
    }

    expect(Raven).to receive(:capture_exception).with(exception, expected_options)

    subject.call(exception, context)
  end

  it "filters out ActiveJob keys" do
    exception = build_exception
    aj_context = context
    aj_context["_aj_globalid"] = "oh noes"
    expected_context = aj_context
    expected_context.delete("_aj_globalid")
    expected_context["_globalid"] = "oh noes"
    expected_options = {
      :message => exception.message,
      :extra => { :sidekiq => expected_context },
      :culprit => "Sidekiq/HardWorker"
    }

    expect(Raven).to receive(:capture_exception).with(exception, expected_options)

    subject.call(exception, aj_context)
  end
end
