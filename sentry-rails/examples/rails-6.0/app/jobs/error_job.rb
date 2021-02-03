class ErrorJob < ApplicationJob
  def perform
    raise "Job failed"
  end
end
