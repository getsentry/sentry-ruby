require 'spec_helper'

require 'raven/integrations/sidekiq/error_handler'

RSpec.describe "Raven::Sidekiq::ErrorHandler" do
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
      :extra => { :sidekiq => context }
    }

    expect(Raven).to receive(:capture_exception).with(exception, expected_options)

    Raven::Sidekiq::ErrorHandler.new.call(exception, context)
  end

  context "when the captured exception is already annotated" do
    it "does a deep merge of options" do
      exception = build_exception
      Raven.annotate_exception(exception, :extra => { :job_title => "engineer" })
      expected_options = {
        :message => exception.message,
        :extra => {
          :sidekiq => context,
          :job_title => "engineer"
        }
      }

      expect(Raven::Event).to receive(:new).with(hash_including(expected_options))

      Raven::Sidekiq::ErrorHandler.new.call(exception, context)
    end
  end

  it "filters out ActiveJob keys", :rails => true do
    exception = build_exception
    aj_context = context
    aj_context["_aj_globalid"] = GlobalID.new('gid://app/model/id')
    expected_context = aj_context.dup
    expected_context.delete("_aj_globalid")
    expected_context["globalid"] = "gid://app/model/id"
    expected_options = {
      :message => exception.message,
      :extra => { :sidekiq => expected_context }
    }
    expect(Raven).to receive(:capture_exception).with(exception, expected_options)

    Raven::Sidekiq::ErrorHandler.new.call(exception, aj_context)
  end
end
