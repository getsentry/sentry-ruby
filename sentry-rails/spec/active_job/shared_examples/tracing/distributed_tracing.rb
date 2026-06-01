# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that supports distributed tracing" do
  it_behaves_like "an ActiveJob backend that emits a producer span on enqueue"
  it_behaves_like "an ActiveJob backend that propagates trace context through the job payload"
  it_behaves_like "an ActiveJob backend that records messaging span data on the consumer transaction"
  it_behaves_like "an ActiveJob backend that propagates Sentry user context through job payloads"
  it_behaves_like "an ActiveJob backend that isolates Sentry context per worker thread"
end
