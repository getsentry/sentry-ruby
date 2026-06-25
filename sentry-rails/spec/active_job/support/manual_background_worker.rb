# frozen_string_literal: true

# A background worker stand-in that captures posted work without running it,
# so a spec can deterministically simulate a worker that exits before flushing
# its queue (#drop!) versus one that drains cleanly (#flush).
class ManualBackgroundWorker
  attr_reader :pending

  def initialize
    @pending = []
  end

  # Mirrors Sentry::BackgroundWorker#perform; a truthy return keeps
  # Client#capture_event from recording a :queue_overflow lost event.
  def perform(&block)
    @pending << block
    true
  end

  def flush
    @pending.each(&:call)
    @pending.clear
  end

  # Simulate a hard worker exit: queued events are lost.
  def drop!
    @pending.clear
  end

  def shutdown; end
end
