require "net/http"

module Sentry
  module Net
    module HTTP
      OP_NAME = "net.http"

      def request(req, body = nil, &block)
        super.tap do |res|
          record_sentry_breadcrumb(req, res)
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

      def record_sentry_breadcrumb(req, res)
        if Sentry.initialized? && Sentry.configuration.breadcrumbs_logger.include?(:http_logger)
          return if from_sentry_sdk?

          request_info = extract_request_info(req)
          crumb = Sentry::Breadcrumb.new(
            level: :info,
            category: OP_NAME,
            type: :info,
            data: {
              method: request_info[:method],
              url: request_info[:url],
              status: res.code.to_i
            }
          )
          Sentry.add_breadcrumb(crumb)
        end
      end

      def record_sentry_span(req, res)
        if Sentry.initialized? && @sentry_span
          request_info = extract_request_info(req)
          @sentry_span.set_description("#{request_info[:method]} #{request_info[:url]}")
          @sentry_span.set_data(:status, res.code.to_i)
        end
      end

      def start_sentry_span
        if Sentry.initialized? && transaction = Sentry.get_current_scope.get_transaction
          return if from_sentry_sdk?
          return if transaction.sampled == false

          child_span = transaction.start_child(op: OP_NAME, start_timestamp: Sentry.utc_now.to_f)
          @sentry_span = child_span
        end
      end

      def finish_sentry_span
        if Sentry.initialized? && @sentry_span
          @sentry_span.set_timestamp(Sentry.utc_now.to_f)
          @sentry_span = nil
        end
      end

      def from_sentry_sdk?
        dsn = Sentry.configuration.dsn
        dsn && dsn.host == self.address
      end

      def extract_request_info(req)
        uri = req.uri
        url = "#{uri.scheme}://#{uri.host}#{uri.path}" rescue uri.to_s
        { method: req.method, url: url }
      end
    end
  end
end

Sentry.register_patch do
  patch = Sentry::Net::HTTP
  Net::HTTP.send(:prepend, patch) unless Net::HTTP.ancestors.include?(patch)
end
