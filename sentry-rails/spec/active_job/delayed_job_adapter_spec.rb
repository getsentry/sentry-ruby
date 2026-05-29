# frozen_string_literal: true

require "spec_helper"

# delayed_job 4.2+ ships an ActiveJob adapter that inherits from
# ActiveJob::QueueAdapters::AbstractAdapter, which only exists in Rails 7.2+.
# On older Rails, instantiating the adapter raises NameError, so skip the
# whole file. Bail out before loading delayed_job so old matrices don't trip
# on the gem either.
return if RAILS_VERSION < 7.2

# delayed_job is gated in the Gemfile by platform (skipped on JRuby).
# Matrices that don't bundle it won't have it available — rescue LoadError
# and skip the whole file so they don't blow up on the
# `include_context "delayed_job adapter"` below.
begin
  require "delayed_job"
  require "delayed_job_active_record"
rescue LoadError
  return
end

RSpec.describe "Sentry + ActiveJob on the delayed_job adapter", type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include_context "active_job backend harness", adapter: :delayed_job
  include_context "delayed_job adapter"

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"
end
