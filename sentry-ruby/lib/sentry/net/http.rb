require "net/http"

module Sentry
  module Net
    module HTTP
      def request(req, body = nil, &block)
        res = super

        if @sentry_span
          @sentry_span.set_description("#{req.method} #{req.uri}")
          @sentry_span.set_data(:status, res.code.to_i)
        end

        res
      end

      def do_start
        return_value = super

        if Sentry.initialized? && transaction = Sentry.get_current_scope.get_transaction
          return return_value if transaction.sampled == false

          child_span = transaction.start_child(op: "net.http", start_timestamp: Sentry.utc_now.to_f)
          @sentry_span = child_span
        end

        return_value
      end

      def do_finish
        return_value = super

        if Sentry.initialized? && @sentry_span
          @sentry_span.set_timestamp(Sentry.utc_now.to_f)
          @sentry_span = nil
        end

        return_value
      end
    end
  end
end

Net::HTTP.send(:prepend, Sentry::Net::HTTP)
