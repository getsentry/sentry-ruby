# frozen_string_literal: true

module Sentry
  module Sequel
    OP_NAME = "db.sql.sequel"
    SPAN_ORIGIN = "auto.db.sequel"

    # Sequel Database extension module that instruments queries
    module DatabaseExtension
      def log_connection_yield(sql, conn, args = nil)
        return super unless Sentry.initialized?

        Sentry.with_child_span(op: OP_NAME, start_timestamp: Sentry.utc_now.to_f, origin: SPAN_ORIGIN) do |span|
          result = super

          if span
            span.set_description(sql)
            span.set_data(Span::DataConventions::DB_SYSTEM, database_type.to_s)
            span.set_data(Span::DataConventions::DB_NAME, opts[:database]) if opts[:database]
            span.set_data(Span::DataConventions::SERVER_ADDRESS, opts[:host]) if opts[:host]
            span.set_data(Span::DataConventions::SERVER_PORT, opts[:port]) if opts[:port]
          end

          result
        end
      end
    end
  end

  ::Sequel::Database.register_extension(:sentry, Sentry::Sequel::DatabaseExtension)
end

Sentry.register_patch(:sequel) do
  ::Sequel::Database.extension(:sentry) if defined?(::Sequel::Database)
end
