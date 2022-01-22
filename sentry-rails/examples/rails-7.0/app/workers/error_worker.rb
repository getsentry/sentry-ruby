class ErrorWorker
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform
    a = 1
    raise "Worker failed"
  end
end
