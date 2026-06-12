# frozen_string_literal: true

require "spec_helper"

# resque 3+ ships an ActiveJob adapter that inherits from
# ActiveJob::QueueAdapters::AbstractAdapter, which only exists in Rails 7.2+.
# On older Rails, instantiating the adapter raises NameError, so skip the
# whole file. Bail out before loading resque so old matrices don't trip on
# the gem either.
return if RAILS_VERSION < 7.2

# resque (and mock_redis) are gated in the Gemfile by platform (skipped on
# JRuby). Matrices that don't bundle them won't have them available —
# rescue LoadError and skip the whole file so they don't blow up on the
# `include_context "resque adapter"` below.
begin
  require "mock_redis"
  require "resque"
  require "resque-scheduler"
rescue LoadError
  return
end

RSpec.describe "Sentry + ActiveJob on the resque adapter", type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include_context "active_job backend harness", adapter: :resque
  include_context "resque adapter"

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"
end
