class ErrorJob < ApplicationJob
  self.queue_adapter = :async

  def perform
    raise "Job failed"
  end
end
