require "spec_helper"
require "active_job"
require "sentry/rails/active_job_context_filter"

RSpec.describe Sentry::Rails::ActiveJobContextFilter do
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
  end

  describe "#transaction_name" do
    subject(:context_filter) { described_class.new(context) }

    context "when the context is a job" do
      let(:context) { { "class" => "FooJob" } }

      it "extracts the class" do
        expect(context_filter.transaction_name).to eq("ActiveJob/FooJob")
      end
    end

    context "when the context is a wrapped job" do
      let(:context) { { "wrapped" => "FooJob", "class" => "WrapperJob" } }

      it "extracts the wrapped class" do
        expect(context_filter.transaction_name).to eq("ActiveJob/FooJob")
      end
    end

    context "when the context is a nested job" do
      let(:context) { { job: { "class" => "FooJob" } } }

      it "extracts the class" do
        expect(context_filter.transaction_name).to eq("ActiveJob/FooJob")
      end
    end

    context "when the context is a wrapped nested job" do
      let(:context) { { job: { "wrapped" => "FooJob", "class" => "WrapperJob" } } }

      it "extracts the wrapped class" do
        expect(context_filter.transaction_name).to eq("ActiveJob/FooJob")
      end
    end

    context "when the context is an event" do
      let(:context) { { event: "startup" } }

      it "extracts the event name" do
        expect(context_filter.transaction_name).to eq("ActiveJob/startup")
      end
    end

    context "when the context is for something else" do
      let(:context) { { foo: "bar" } }

      it "extracts nothing" do
        expect(context_filter.transaction_name).to eq("ActiveJob")
      end
    end
  end
end
