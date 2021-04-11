require "net/http"

module Sentry
  module Net
    module HTTP
      def request(req, body = nil, &block)
        super.tap do |res|
          record_sentry_span(req, res)
        end
      end

      def do_start
        super.tap do
          start_sentry_span
        end
      end

      def do_finish
        super.tap do
          finish_sentry_span
        end
      end

      private

      def record_sentry_span(req, res)
        if Sentry.initialized? && @sentry_span
          @sentry_span.set_description("#{req.method} #{req.uri}")
          @sentry_span.set_data(:status, res.code.to_i)
        end
      end

      def start_sentry_span
        if Sentry.initialized? && transaction = Sentry.get_current_scope.get_transaction
          return if transaction.sampled == false

          child_span = transaction.start_child(op: "net.http", start_timestamp: Sentry.utc_now.to_f)
          @sentry_span = child_span
        end
      end

      def finish_sentry_span
        if Sentry.initialized? && @sentry_span
          @sentry_span.set_timestamp(Sentry.utc_now.to_f)
          @sentry_span = nil
        end
      end
    end
  end
end

Net::HTTP.send(:prepend, Sentry::Net::HTTP)
