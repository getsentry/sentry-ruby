# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that preserves the job return value" do
  let(:returning_job) do
    job_fixture do
      def perform
        "return value from job"
      end
    end
  end

  it "returns the job's perform value from perform_now" do
    result = returning_job.perform_now
    expect(result).to eq("return value from job")
  end
end
