class ErrorWorker
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform
    raise "Worker failed"
  end
end
