# frozen_string_literal: true

require "sentry/rails/active_job_extension"
require "sentry/delayed_job/active_job_support/plugin"

module Sentry
  module DelayedJob
    # The extension sentry-rails uses for ActiveJob jobs on delayed_job when the
    # app lets sentry-rails report them. It keeps sentry-delayed_job's context,
    # tags, origin and integration, so these jobs look the same in Sentry in
    # either mode.
    #
    # @see ActiveJobSupport
    class ActiveJobExtension < Sentry::Rails::ActiveJobExtension
      def initialize(name: :delayed_job, integration: Sentry::DelayedJob, origin: Plugin::SPAN_ORIGIN, **dependencies)
        super(name: name, integration: integration, origin: origin, **dependencies)
      end

      # Adds sentry-delayed_job's `Active-Job` context and `delayed_job.*` tags.
      #
      # @see Sentry::JobExtensions::Extension#scope_data
      def scope_data(job:, **)
        tags = { "delayed_job.queue" => job.queue_name }
        record_id = job._sentry&.[](ActiveJobSupport::RECORD_ID_KEY)
        tags["delayed_job.id"] = record_id if record_id

        { contexts: { Plugin::ACTIVE_JOB_CONTEXT_KEY => ActiveJobSupport.active_job_context(job._sentry_job_data) }, tags: tags }
      end
    end

    Sentry::Rails.register_active_job_extension(:delayed_job, ActiveJobExtension.new)
  end
end
