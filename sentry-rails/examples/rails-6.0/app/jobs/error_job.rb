class ErrorJob < ApplicationJob
  def perform
    1 / 0
  end
end
