module Raven
  class Rails
    module Overrides
      module DebugExceptionsCatcher
        def render_exception(env_or_request, exception)
          begin
            env = env_or_request.respond_to?(:env) ? env_or_request.env : env_or_request
            Raven::Rack.capture_exception(exception, env)
          rescue
          end
          super
        end
      end

      module OldDebugExceptionsCatcher
        def self.included(base)
          base.send(:alias_method_chain, :render_exception, :raven)
        end

        def render_exception_with_raven(env_or_request, exception)
          begin
            env = env_or_request.respond_to?(:env) ? env_or_request.env : env_or_request
            Raven::Rack.capture_exception(exception, env)
          rescue
          end
          render_exception_without_raven(env_or_request, exception)
        end
      end
    end
  end
end
