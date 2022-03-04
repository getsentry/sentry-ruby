class ErrorJob < ApplicationJob
  self.queue_adapter = :resque

  def perform
    a = 1
    b = 2
    raise "Job failed"
  end
end
