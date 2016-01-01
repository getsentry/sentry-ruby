module Raven
  class Rails
    module Middleware
      module PublicExceptionsCatcher
        def self.included(base)
          base.send(:alias_method_chain, :call, :raven)
        end

        def call_with_raven(env)
          Raven::Rack.capture_exception(env['action_dispatch.exception'], env)
          call_without_raven(env)
        end
      end
    end
  end
end
