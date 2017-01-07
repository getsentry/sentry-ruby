require 'rake'
require 'rake/task'
require 'raven/integrations/tasks'

module Rake
  class Application
    alias orig_display_error_messsage display_error_message
    def display_error_message(ex)
      Raven.capture_exception ex, :logger => 'rake', :tags => { 'rake_task' => top_level_tasks.join(' ') }
      orig_display_error_messsage(ex)
    end
  end
end
