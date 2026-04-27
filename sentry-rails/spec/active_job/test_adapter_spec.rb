# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sentry + ActiveJob on the test adapter", type: :job do
  include_context "active_job backend harness", adapter: :test

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
end
