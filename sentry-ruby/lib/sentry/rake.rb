require "rake"
require "rake/task"

module Sentry
  module Rake
    module Application
      def display_error_message(ex)
        Sentry.capture_exception(ex) do |scope|
          task_name = top_level_tasks.join(' ')
          scope.set_transaction_name(task_name)
          scope.set_tag("rake_task", task_name)
        end if Sentry.initialized? && !Sentry.configuration.skip_rake_integration

        super
      end
    end

    module Task
      def execute(args=nil)
        return super unless Sentry.initialized? && Sentry.get_current_hub

        super
      end
    end
  end
end

Rake::Application.prepend(Sentry::Rake::Application)
Rake::Task.prepend(Sentry::Rake::Task)
