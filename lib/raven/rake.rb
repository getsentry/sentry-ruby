require 'raven'
require 'rake/task'

# Monkey patch Rake::Task#execute to capture and report exceptions on sentry
# Include this file in an initializer 
module Rake
  class Task
    alias :orig_execute :execute
    def execute(args = nil)
      Raven.capture :logger => 'rake', :tags => { 'rake_task' => @name } do
        orig_execute(args)
      end
    end
  end
end
 
