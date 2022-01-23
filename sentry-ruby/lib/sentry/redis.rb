# frozen_string_literal: true

module Sentry
  # @api private
  module Redis
    OP_NAME ||= "db.redis.command"

    extend self

    def instrument(commands, host, port, db)
      return yield unless Sentry.initialized?

      @commands, @host, @port, @db = commands, host, port, db

      record_span do
        yield.tap do
          record_breadcrumb
        end
      end
    end

    private

    def record_span
      return yield unless (transaction = Sentry.get_current_scope.get_transaction) && transaction.sampled

      transaction.start_child(op: OP_NAME, start_timestamp: Sentry.utc_now.to_f).then do |sentry_span|
        yield.tap do
          sentry_span.set_description(commands_description)
          sentry_span.set_data(:server, server_description)
          sentry_span.set_timestamp(Sentry.utc_now.to_f)
        end
      end
    end

    def record_breadcrumb
      return unless Sentry.configuration.breadcrumbs_logger.include?(:redis_logger)

      Sentry.add_breadcrumb(
        Sentry::Breadcrumb.new(
          level: :info,
          category: OP_NAME,
          type: :info,
          data: {
            commands: parsed_commands,
            server: server_description
          }
        )
      )
    end

    def commands_description
      parsed_commands.map do |statement|
        statement.values.join(" ").strip
      end.join(", ")
    end

    def parsed_commands
      @commands.map do |statement|
        command, key, *_values = statement

        { command: command.to_s.upcase, key: key }
      end
    end

    def server_description
      "#{@host}:#{@port}/#{@db}"
    end

    module Client
      def logging(commands, &block)
        Sentry::Redis.instrument(commands, host, port, db) do
          super
        end
      end
    end
  end
end

if defined?(::Redis::Client)
  Sentry.register_patch do
    patch = Sentry::Redis::Client
    Redis::Client.prepend(patch) unless Redis::Client.ancestors.include?(patch)
  end
end
