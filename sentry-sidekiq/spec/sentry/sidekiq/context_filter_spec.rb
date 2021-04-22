require "spec_helper"

RSpec.describe Sentry::Sidekiq::ContextFilter do
  describe "#filtered" do
    subject(:context_filter) { described_class.new(context) }

    context "filters out ActiveJob keys from context" do
      let(:context) do
        { :_aj_globalid => "gid://app/model/id", :key => "value" }
      end

      it "removes reserved keys" do
        expect(context_filter.filtered).to eq("globalid" => "gid://app/model/id", :key => "value")
      end
    end

    context "filters out ActiveJob keys from nested context" do
      let(:context) do
        {
          :_aj_globalid => "gid://app/model/id",
          :arguments => { :key => "value", :_aj_symbol_keys => ["key"] }
        }
      end
      let(:expected_context) do
        {
          "globalid" => "gid://app/model/id",
          :arguments => { :key => "value", "symbol_keys" => ["key"] }
        }
      end

      it "removes reserved keys" do
        expect(context_filter.filtered).to eq(
          "globalid" => "gid://app/model/id",
          :arguments => { :key => "value", "symbol_keys" => ["key"] }
        )
      end
    end

    context "with job entry in the context" do
      let(:context) do
        {
          context: "Job raised exception",
          job: {
            "retry"=>0,
            "queue"=>"default",
            "class"=>"ErrorWorker",
            "args"=>[],
            "jid"=>"6dd2b3862d0e4b637c08a567",
            "created_at"=>1619077597.620555,
            "enqueued_at"=>1619077597.620651
          },
          jobstr: "STR"
        }
      end
      it "flattens the job entry" do
        expect(context_filter.filtered).to eq(
          {
            context: "Job raised exception",
            "retry"=>0,
            "queue"=>"default",
            "class"=>"ErrorWorker",
            "args"=>[],
            "jid"=>"6dd2b3862d0e4b637c08a567",
            "created_at"=>1619077597.620555,
            "enqueued_at"=>1619077597.620651,
            jobstr: "STR"
          }
        )
      end
    end
  end

  describe "#transaction_name" do
    subject(:context_filter) { described_class.new(context) }

    context "when the context is a job" do
      let(:context) { { "class" => "FooJob" } }

      it "extracts the class" do
        expect(context_filter.transaction_name).to eq("Sidekiq/FooJob")
      end
    end

    context "when the context is a wrapped job" do
      let(:context) { { "wrapped" => "FooJob", "class" => "WrapperJob" } }

      it "extracts the wrapped class" do
        expect(context_filter.transaction_name).to eq("Sidekiq/FooJob")
      end
    end

    context "when the context is a nested job" do
      let(:context) { { job: { "class" => "FooJob" } } }

      it "extracts the class" do
        expect(context_filter.transaction_name).to eq("Sidekiq/FooJob")
      end
    end

    context "when the context is a wrapped nested job" do
      let(:context) { { job: { "wrapped" => "FooJob", "class" => "WrapperJob" } } }

      it "extracts the wrapped class" do
        expect(context_filter.transaction_name).to eq("Sidekiq/FooJob")
      end
    end

    context "when the context is an event" do
      let(:context) { { event: "startup" } }

      it "extracts the event name" do
        expect(context_filter.transaction_name).to eq("Sidekiq/startup")
      end
    end

    context "when the context is for something else" do
      let(:context) { { foo: "bar" } }

      it "extracts nothing" do
        expect(context_filter.transaction_name).to eq("Sidekiq")
      end
    end
  end
end
