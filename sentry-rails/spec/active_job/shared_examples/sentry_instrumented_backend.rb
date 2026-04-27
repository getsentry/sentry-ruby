# frozen_string_literal: true

RSpec.shared_examples "a Sentry-instrumented ActiveJob backend" do
  it_behaves_like "an ActiveJob backend that captures errors"
  it_behaves_like "an ActiveJob backend that respects retry semantics"
end
