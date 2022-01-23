# frozen_string_literal: true

module Sentry
  # @api private
  module Redis
    module Client
      OP_NAME = "db.redis.command"

      def logging(commands, &block)
        instrument_for_sentry(commands) do
          super
        end
      end

      private

      def instrument_for_sentry(commands)
        return yield unless Sentry.initialized?

        record_sentry_span(commands) do
          yield.tap do
            record_sentry_breadcrumb(commands)
          end
        end
      end

      def record_sentry_span(commands)
        return yield unless (transaction = Sentry.get_current_scope.get_transaction) && transaction.sampled

        transaction.start_child(op: OP_NAME, start_timestamp: Sentry.utc_now.to_f).then do |sentry_span|
          yield.tap do
            sentry_span.set_description(generate_description(commands))
            sentry_span.set_data(:server, server_description)
            sentry_span.set_timestamp(Sentry.utc_now.to_f)
          end
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
              commands: parse_commands(commands),
              server: server_description
            }
          )
        )
      end

      def generate_description(commands)
        parse_commands(commands).map do |statement|
          statement.values.join(" ").strip
        end.join(", ")
      end

      def parse_commands(commands)
        commands.map do |statement|
          command, key, *_values = statement

          { command: command.to_s.upcase, key: key }
        end
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
