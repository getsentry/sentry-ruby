# frozen_string_literal: true

require "sentry/rails/active_job_extension"

module Sentry
  module Sidekiq
    # The extension sentry-rails uses for ActiveJob jobs on Sidekiq when the app
    # lets sentry-rails report them. It keeps Sidekiq's transaction names, origin
    # and integration, so these jobs look the same in Sentry in either mode.
    #
    # @see ActiveJobSupport
    class ActiveJobExtension < Sentry::Rails::ActiveJobExtension
      def initialize(name: :sidekiq_active_job, integration: Sentry::Sidekiq, origin: JobExtension::SPAN_ORIGIN, **dependencies)
        super(name: name, integration: integration, origin: origin, **dependencies)
      end

      # Leaves the `queue.publish` span to {SentryContextClientMiddleware}.
      #
      # @see Sentry::JobExtensions::Extension#record_publish_span?
      def record_publish_span?(job:, **)
        false
      end

      # Identifies the message by its Sidekiq jid, as the `queue.publish` span
      # recorded by {SentryContextClientMiddleware} does.
      #
      # @see Sentry::JobExtensions::Extension#messaging_data
      def messaging_data(job:, **context)
        data = super
        data[:message_id] = job.provider_job_id if job.provider_job_id
        data
      end

      # Names the transaction `Sidekiq/<ActiveJob class>`.
      #
      # @see Sentry::JobExtensions::Extension#transaction_name
      def transaction_name(job:, **)
        "#{JobExtension::SIDEKIQ_NAME}/#{super}"
      end
    end

    Sentry::Rails.register_active_job_extension(:sidekiq, ActiveJobExtension.new)
  end
end
