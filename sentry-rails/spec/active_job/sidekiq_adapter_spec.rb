# frozen_string_literal: true

require "spec_helper"

# These specs only pass on Rails > 7.0 — older Rails/Sidekiq adapter
# combinations expose differences (e.g. enqueue payload shape, retry
# wiring) that the shared examples don't tolerate. Bail out before
# loading Sidekiq so older matrices don't trip on the gem either.
return if RAILS_VERSION <= 7.0

# Sidekiq is also gated in the Gemfile by Ruby version and platform.
# Matrices that don't bundle Sidekiq won't have it available — rescue
# LoadError and skip the whole file so they don't blow up on the
# `include_context "sidekiq adapter"` below.
begin
  require "sidekiq"
  if ::Sidekiq.respond_to?(:testing!)
    ::Sidekiq.testing!(:fake)
  else
    require "sidekiq/testing"
  end
rescue LoadError
  return
end

RSpec.describe "Sentry + ActiveJob on the sidekiq adapter", type: :job do
  include_context "active_job backend harness", adapter: :sidekiq
  include_context "sidekiq adapter"

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"
end
