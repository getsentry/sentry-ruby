module Raven
  module Rails
    module Middleware
      module DebugExceptionsCatcher
        def self.included(base)
          base.send(:alias_method_chain, :render_exception, :raven)
        end

        def render_exception_with_raven(env, exception)
          if exception.class.name != 'ActionController::RoutingError' and exception.class.name != 'ActiveRecord::RecordNotFound'
            evt = Raven::Event.capture_rack_exception(exception, env)
            Raven.send(evt) if evt
          end
          render_exception_without_raven(env, exception)
        end
      end
    end
  end
end
