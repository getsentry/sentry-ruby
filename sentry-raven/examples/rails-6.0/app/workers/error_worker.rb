class ErrorWorker
  include Sidekiq::Worker

  def perform
    1 / 0
  end
end
