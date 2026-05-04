# frozen_string_literal: true

require "spec_helper"

# These examples exercise the `if !Sentry.initialized?` short-circuit in
# ActiveJobExtensions#perform_now.  They MUST run with Sentry not initialized,
# so each example resets all SDK globals before running.
RSpec.describe "ActiveJob without Sentry initialized", type: :job do
  around do |example|
    reset_sentry_globals!
    example.run
  end

  it "runs the job normally (raises the original error)" do
    expect { FailedJob.perform_now }.to raise_error(FailedJob::TestError)
  end

  it "returns the #perform method's return value" do
    expect(NormalJob.perform_now).to eq("foo")
  end
end
