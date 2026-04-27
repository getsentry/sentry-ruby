# frozen_string_literal: true

require "spec_helper"

if Gem::Version.new(Rails.version) >= Gem::Version.new("7.1")
  require "solid_queue"
end

RSpec.describe "Sentry + ActiveJob on SolidQueue", skip: Gem::Version.new(Rails.version) < Gem::Version.new("7.1") do
  include ActiveSupport::Testing::TimeHelpers
  include_context "active_job backend harness", adapter: :solid_queue

  def boot_adapter(_adapter)
    Sentry::Rails::Test::Application.load_queue_schema
  end

  def reset_adapter(_adapter)
    [
      SolidQueue::ReadyExecution,
      SolidQueue::ClaimedExecution,
      SolidQueue::FailedExecution,
      SolidQueue::BlockedExecution,
      SolidQueue::ScheduledExecution,
      SolidQueue::RecurringExecution,
      SolidQueue::Process,
      SolidQueue::Job
    ].each(&:delete_all)
  end

  def drain(at: nil)
    process = SolidQueue::Process.register(
      kind: "Worker",
      pid: ::Process.pid,
      name: "spec-#{SecureRandom.hex(4)}"
    )

    travel_to(at || Time.current) do
      SolidQueue::ScheduledExecution.dispatch_next_batch(100)
      SolidQueue::ReadyExecution.claim("*", 100, process.id).each(&:perform)
    end
  end

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
end
