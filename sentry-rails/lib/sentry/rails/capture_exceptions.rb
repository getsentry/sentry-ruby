module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
      def initialize(app)
        super

        if defined?(::Sprockets::Rails)
          @assets_regex = %r(\A/{0,2}#{::Rails.application.config.assets.prefix})
        end
      end

      private

      def collect_exception(env)
        super || env["action_dispatch.exception"] || env["sentry.rescued_exception"]
      end

      def transaction_op
        "rails.request".freeze
      end

      def capture_exception(exception)
        current_scope = Sentry.get_current_scope

        if original_transaction = current_scope.rack_env["sentry.original_transaction"]
          current_scope.set_transaction_name(original_transaction)
        end

        Sentry::Rails.capture_exception(exception)
      end

      def start_transaction(env, scope)
        transaction = super

        return unless transaction

        if @assets_regex && transaction.name.match?(@assets_regex)
          transaction.instance_variable_set(:@sampled, false)
        end

        transaction
      end
    end
  end
end
