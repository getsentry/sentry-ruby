require "rake"
require "rake/task"

module Rake
  class Application

    alias orig_display_error_messsage display_error_message
    def display_error_message(ex)
      Sentry.capture_exception(ex, hint: { background: false }) do |scope|
        task_name = top_level_tasks.join(' ')
        scope.set_transaction_name(task_name)
        scope.set_tag("rake_task", task_name)
      end if Sentry.initialized? && !Sentry.configuration.skip_rake_integration

      orig_display_error_messsage(ex)
    end
  end

  class Task
    alias orig_execute execute

    def execute(args=nil)
      return orig_execute(args) unless Sentry.initialized? && Sentry.get_current_hub

      Sentry.get_current_hub.with_background_worker_disabled do
        orig_execute(args)
      end
    end
  end
end
