module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
      def initialize(app)
        super

        if defined?(::Sprockets::Rails)
          @assets_regex = %r(\A/{0,2}#{::Rails.application.config.assets.prefix})
        end

        if ::Rails.application.config.public_file_server.enabled
          @public_file_server_enabled = true
        end
      end

      private

      def collect_exception(env)
        return nil if env["sentry.already_captured"]
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
        sentry_trace = env["HTTP_SENTRY_TRACE"]
        options = { name: scope.transaction_name, op: transaction_op }

        if skip_sampling?(env)
          options.merge!(sampled: false)
        end

        transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, **options) if sentry_trace
        Sentry.start_transaction(transaction: transaction, **options)
      end

      def skip_sampling?(env)
        for_sprockets_assets?(env) || for_static_file?(env)
      end

      def for_sprockets_assets?(env)
        path = env["PATH_INFO"]
        @assets_regex && path.match?(@assets_regex)
      end

      def for_static_file?(env)
        if @public_file_server_enabled
          static_middleware = ::Rails.application.config.middleware.detect { |m| m == ::ActionDispatch::Static }

          return false unless static_middleware

          static_middleware = static_middleware.build(@app)
          file_handler = static_middleware.instance_variable_get(:@file_handler)
          request = ::Rack::Request.new env

          if file_handler.respond_to?(:find_file, true)
            !!file_handler.send(:find_file, request.path_info, accept_encoding: request.accept_encoding)
          else
            path = request.path_info.chomp("/")
            !!file_handler.match?(path)
          end
        end
      end
    end
  end
end
