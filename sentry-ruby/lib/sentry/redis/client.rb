# frozen_string_literal: true

module Sentry
  # @api private
  module Redis
    module Client
      OP_NAME = "redis"

      def logging(commands, &block)
        instrument_for_sentry(commands) do
          super
        end
      end

      private

      def instrument_for_sentry(commands)
        yield unless Sentry.initialized?

        record_sentry_span(commands) do
          yield.tap do
            record_sentry_breadcrumb(commands)
          end
        end
      end

      def record_sentry_span(commands)
        yield unless (transaction = Sentry.get_current_scope.get_transaction) && transaction.sampled

        transaction.start_child(op: OP_NAME, start_timestamp: Sentry.utc_now.to_f).then do |sentry_span|
          yield

          sentry_span.set_description(generate_description(commands))
          sentry_span.set_data(:server, server_description)
          sentry_span.set_timestamp(Sentry.utc_now.to_f)
        end
      end

      def record_sentry_breadcrumb(commands)
        return unless Sentry.configuration.breadcrumbs_logger.include?(:redis_logger)

        Sentry.add_breadcrumb(
          Sentry::Breadcrumb.new(
            level: :info,
            category: OP_NAME,
            type: :info,
            data: {
              command: commands.first.first,
              key: commands.first.second
            }
          )
        )
      end

      def generate_description(commands)
        commands.first.take(2).join(" ")
      end

      def server_description
        "#{host}:#{port}/#{db}"
      end
    end
  end
end

Sentry.register_patch do
  patch = Sentry::Redis
  Redis::Client.prepend(Sentry::Redis::Client) unless Redis::Client.ancestors.include?(patch)
end
