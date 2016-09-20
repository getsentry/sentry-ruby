require 'delayed_job'

module Delayed
  module Plugins
    class Raven < ::Delayed::Plugin
      callbacks do |lifecycle|
        lifecycle.around(:invoke_job) do |job, *args, &block|
          begin
            # Forward the call to the next callback in the callback chain
            block.call(job, *args)

          rescue Exception => exception
            # Log error to Sentry
            #
            # Make sure to convert all Time objects to string so that they
            # can be serialized by ActiveJob
            extra = {
              :delayed_job => {
                :id          => job.id,
                :priority    => job.priority,
                :attempts    => job.attempts,
                :run_at      => job.run_at.to_s,
                :locked_at   => job.locked_at.to_s,
                :locked_by   => job.locked_by.to_s,
                :queue       => job.queue,
                :created_at  => job.created_at.to_s
              }
            }
            # last_error can be nil
            extra[:last_error] = job.last_error[0...100] if job.last_error
            # handlers are YAML objects in strings, we definitely can't
            # report all of that or the event will get truncated randomly
            extra[:handler] = job.handler[0...100] if job.handler

            if job.respond_to?('payload_object') && job.payload_object.respond_to?('job_data')
              # use `.inspect` to convert to a string, as job_data contains
              # restricted keys that cause errors if DelayedJob is used to
              # asynchronously report errors within Raven
              extra[:active_job] = job.payload_object.job_data.inspect
            end
            ::Raven.capture_exception(exception,
                                      :logger  => 'delayed_job',
                                      :tags    => {
                                        :delayed_job_queue => job.queue,
                                        :delayed_job_id => job.id
                                      },
                                      :extra => extra)

            # Make sure we propagate the failure!
            raise exception
          ensure
            ::Raven::Context.clear!
            ::Raven::BreadcrumbBuffer.clear!
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
