# frozen_string_literal: true

RSpec.shared_examples "a Sentry-instrumented ActiveJob backend" do
  it_behaves_like "an ActiveJob backend that captures errors"
  it_behaves_like "an ActiveJob backend that attaches job context to error events"
  it_behaves_like "an ActiveJob backend that isolates per-job scope"
  it_behaves_like "an ActiveJob backend that respects rescue_from"
  it_behaves_like "an ActiveJob backend that respects skippable_job_adapters"
  it_behaves_like "an ActiveJob backend that serializes complex arguments"
  it_behaves_like "an ActiveJob backend that respects retry semantics"
  it_behaves_like "an ActiveJob backend that respects discard semantics"
end
