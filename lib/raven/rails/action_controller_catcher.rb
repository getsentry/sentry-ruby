module Raven
  module Rails
    module ActionControllerCatcher

      def self.included(base)
        base.send(:alias_method, :rescue_action_in_public_without_raven, :rescue_action_in_public)
        base.send(:alias_method, :rescue_action_in_public, :rescue_action_in_public_with_raven)
        base.send(:alias_method, :rescue_action_locally_without_raven, :rescue_action_locally)
        base.send(:alias_method, :rescue_action_locally, :rescue_action_locally_with_raven)
      end

      private

      def rescue_action_in_public_with_raven(exception)
        evt = Raven::Event.capture_rack_exception(exception, request.env)
        Raven.send(evt) if evt
        rescue_action_in_public_without_raven(exception)
      end

      def rescue_action_locally_with_raven(exception)
        evt = Raven::Event.capture_rack_exception(exception, request.env)
        Raven.send(evt) if evt
        rescue_action_locally_without_raven(exception)
      end

    end
  end
end
