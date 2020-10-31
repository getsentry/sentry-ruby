module Sentry
  module Rails
    module Overrides
      module DebugExceptionsCatcher
        def render_exception(env_or_request, exception)
          begin
            env = env_or_request.respond_to?(:env) ? env_or_request.env : env_or_request
            Sentry.with_scope do |scope|
              scope.set_rack_env(env)
              Sentry.capture_exception(exception)
            end
          rescue
          end
          super
        end
      end
    end
  end
end
