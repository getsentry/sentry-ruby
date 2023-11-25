# frozen_string_literal: true

require "net/http"
require "resolv"

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
          request_info = extract_request_info(req)

          if propagate_trace?(request_info[:url], Sentry.configuration)
            set_propagation_headers(req)
          end

          super.tap do |res|
            record_sentry_breadcrumb(request_info, res)

            if sentry_span
              sentry_span.set_description("#{request_info[:method]} #{request_info[:url]}")
              sentry_span.set_data(Span::DataConventions::URL, request_info[:url])
              sentry_span.set_data(Span::DataConventions::HTTP_METHOD, request_info[:method])
              sentry_span.set_data(Span::DataConventions::HTTP_QUERY, request_info[:query]) if request_info[:query]
              sentry_span.set_data(Span::DataConventions::HTTP_STATUS_CODE, res.code.to_i)
            end
          end
        end
      end

      private

      def set_propagation_headers(req)
        Sentry.get_trace_propagation_headers&.each { |k, v| req[k] = v }
      end

      def record_sentry_breadcrumb(request_info, res)
        return unless Sentry.initialized? && Sentry.configuration.breadcrumbs_logger.include?(:http_logger)

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
        # IPv6 url could look like '::1/path', and that won't parse without
        # wrapping it in square brackets.
        hostname = address =~ Resolv::IPv6::Regex ? "[#{address}]" : address
        uri = req.uri || URI.parse("#{use_ssl? ? 'https' : 'http'}://#{hostname}#{req.path}")
        url = "#{uri.scheme}://#{uri.host}#{uri.path}" rescue uri.to_s

        result = { method: req.method, url: url }

        if Sentry.configuration.send_default_pii
          result[:query] = uri.query
          result[:body] = req.body
        end

        result
      end

      def propagate_trace?(url, configuration)
        url &&
          configuration.propagate_traces &&
          configuration.trace_propagation_targets.any? { |target| url.match?(target) }
      end
    end
  end
end

Sentry.register_patch(:http, Sentry::Net::HTTP, Net::HTTP)
