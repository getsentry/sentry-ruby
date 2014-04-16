if defined?(Delayed)
  require 'delayed_job'

  module Delayed
    module Plugins

      class Raven < ::Delayed::Plugin
        callbacks do |lifecycle|
          lifecycle.around(:invoke_job) do |job, *args, &block|
            begin
              # Forward the call to the next callback in the callback chain
              block.call(job, *args)

            rescue Exception => error
              # Log error to Sentry
              ::Raven.capture_exception(error, { delayed_job: job.inspect })

              # Make sure we propagate the failure!
              raise error
            end
          end
        end
      end

    end
  end

  ##
  # Register DelayedJob Raven plugin
  #
  Delayed::Worker.plugins << Delayed::Plugins::Raven
end
