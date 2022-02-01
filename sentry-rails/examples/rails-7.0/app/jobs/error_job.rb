class ErrorJob < ApplicationJob
  self.queue_adapter = :async

  def perform
    a = 1
    b = 2
    raise "Job failed"
  end
end
