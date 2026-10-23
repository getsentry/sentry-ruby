# frozen_string_literal: true

module Sentry
  module Resque
    class Railtie < ::Rails::Railtie
      initializer "sentry.resque.active_job_extension" do
        ActiveSupport.on_load(:active_job) do
          require "sentry/resque/active_job_extension" if defined?(::Sentry::Rails::ActiveJobExtension)
        end
      end

      config.after_initialize do
        next unless Sentry.initialized? && defined?(::Sentry::Rails)
        next if Sentry.configuration.resque.active_job_integration == :rails

        Sentry.configuration.rails.skippable_job_adapters << ActiveJobSupport::ACTIVE_JOB_ADAPTER
      end
    end
  end
end
