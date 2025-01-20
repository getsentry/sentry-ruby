class ErrorJob < ApplicationJob
  queue_as :default

  def perform(*args)
    foo
  end
end
