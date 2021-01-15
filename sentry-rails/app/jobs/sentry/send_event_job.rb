module Sentry
  parent_job =
    if defined?(ApplicationJob)
      ApplicationJob
    else
      ActiveJob::Base
    end

  class SendEventJob < parent_job
    self.log_arguments = false if ::Rails.version.to_f >= 6.1
    discard_on ActiveJob::DeserializationError # this will prevent infinite loop when there's an issue deserializing SentryJob

    def perform(event, hint = {})
      Sentry.send_event(event, hint)
    end
  end
end

