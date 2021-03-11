Sentry.init do |config|
  config.breadcrumbs_logger = [:active_support_logger]
  config.background_worker_threads = 0
  config.send_default_pii = true
  config.traces_sample_rate = 1.0 # set a float between 0.0 and 1.0 to enable performance monitoring
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
  config.release = `git branch --show-current`
  # you can use the pre-defined job for the async callback
  #
  # config.async = lambda do |event, hint|
  #   Sentry::SendEventJob.perform_later(event, hint)
  # end
end
