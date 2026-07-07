# frozen_string_literal: true

module Sentry
  module Rails
    # Establishes the propagation context as early as possible, so anything
    # logged before +CaptureExceptions+ runs shares the request's trace_id.
    class CaptureContext
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Sentry.initialized?

        Sentry.clone_hub_to_current_thread
        Sentry.get_current_scope.generate_propagation_context(env)
        env[Sentry::PropagationContext::ESTABLISHED_ENV_KEY] = true

        @app.call(env)
      end
    end
  end
end
