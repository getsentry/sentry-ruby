# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sentry + ActiveJob on the test adapter", type: :job do
  include_context "active_job backend harness", adapter: :test

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that records messaging span data on the consumer transaction"
  it_behaves_like "an ActiveJob backend that emits a producer span on enqueue"
  it_behaves_like "an ActiveJob backend that propagates trace context through the job payload"
  it_behaves_like "an ActiveJob backend that propagates Sentry user context through job payloads"
  it_behaves_like "an ActiveJob backend that isolates Sentry context per worker thread"
end
