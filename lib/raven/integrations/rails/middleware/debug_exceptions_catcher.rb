module Raven
  class Rails
    module Middleware
      module DebugExceptionsCatcher
        def self.included(base)
          base.send(:alias_method_chain, :render_exception, :raven)
        end

        def render_exception_with_raven(env_or_request, exception)
          env = env_or_request.respond_to?(:env) ? env_or_request.env : env_or_request
          Raven::Rack.capture_exception(exception, env)
        ensure
          render_exception_without_raven(env, exception)
        end
      end
    end
  end
end
