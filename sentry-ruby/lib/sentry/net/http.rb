# frozen_string_literal: true

require "net/http"

module Sentry
  # @api private
  module Net
    module HTTP
      OP_NAME = "http.client"
      BREADCRUMB_CATEGORY = "net.http"

      # To explain how the entire thing works, we need to know how the original Net::HTTP#request works
      # Here's part of its definition. As you can see, it usually calls itself inside a #start block
      #
      # ```
      # def request(req, body = nil, &block)
      #   unless started?
      #     start {
      #       req['connection'] ||= 'close'
      #       return request(req, body, &block) # <- request will be called for the second time from the first call
      #     }
      #   end
      #   # .....
      # end
      # ```
      #
      # So we're only instrumenting request when `Net::HTTP` is already started
      def request(req, body = nil, &block)
        return super unless started? && Sentry.initialized?
        return super if from_sentry_sdk?

        Sentry.with_child_span(op: OP_NAME, start_timestamp: Sentry.utc_now.to_f) do |sentry_span|
          set_sentry_trace_header(req, sentry_span)

          super.tap do |res|
            record_sentry_breadcrumb(req, res)

            if sentry_span
              request_info = extract_request_info(req)
              sentry_span.set_description("#{request_info[:method]} #{request_info[:url]}")
              sentry_span.set_data(:status, res.code.to_i)
            end
          end
        end
      end

      private

      def set_sentry_trace_header(req, sentry_span)
        return unless sentry_span

        client = Sentry.get_current_client

        trace = client.generate_sentry_trace(sentry_span)
        req[SENTRY_TRACE_HEADER_NAME] = trace if trace

        baggage = client.generate_baggage(sentry_span)
        req[BAGGAGE_HEADER_NAME] = baggage if baggage && !baggage.empty?
      end

      def record_sentry_breadcrumb(req, res)
        return unless Sentry.initialized? && Sentry.configuration.breadcrumbs_logger.include?(:http_logger)

        request_info = extract_request_info(req)

        crumb = Sentry::Breadcrumb.new(
          level: :info,
          category: BREADCRUMB_CATEGORY,
          type: :info,
          data: {
            status: res.code.to_i,
            **request_info
          }
        )
        Sentry.add_breadcrumb(crumb)
      end

      def from_sentry_sdk?
        dsn = Sentry.configuration.dsn
        dsn && dsn.host == self.address
      end

      def extract_request_info(req)
        uri = req.uri || URI.parse("#{use_ssl? ? 'https' : 'http'}://#{address}#{req.path}")
        url = "#{uri.scheme}://#{uri.host}#{uri.path}" rescue uri.to_s

        result = { method: req.method, url: url }

        if Sentry.configuration.send_default_pii
          result[:url] = result[:url] + "?#{uri.query}"
          result[:body] = req.body
        end

        result
      end
    end
  end
end

Sentry.register_patch(Sentry::Net::HTTP, Net::HTTP)
