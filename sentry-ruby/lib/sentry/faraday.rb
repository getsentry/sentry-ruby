# frozen_string_literal: true

require "faraday"

module Sentry
  module Faraday
    OP_NAME = "http.client"
    SPAN_ORIGIN = "auto.http.faraday"
    BREADCRUMB_CATEGORY = "http"

    module Connection
      # Since there's no way to preconfigure Faraday connections and add our instrumentation
      # by default, we need to extend the connection constructor and do it there
      #
      # @see https://lostisland.github.io/faraday/#/customization/index?id=configuration
      def new(url = nil, options = nil)
        super.tap do |connection|
          # Ensure that we attach instrumentation only if the adapter is not net/http
          # because if is is, then the net/http instrumentation will take care of it
          if connection.builder.adapter.name != "Faraday::Adapter::NetHttp"
            connection.request :instrumentation, name: OP_NAME, instrumenter: Instrumenter.new

            # Make sure that it's going to be the first middleware so that it can capture
            # the entire request processing involving other middlewares
            handlers = connection.builder.handlers
            instrumentation = handlers.pop

            handlers.unshift(instrumentation)
          end
        end
      end
    end

    Sentry.register_patch(:faraday) do
      ::Faraday::Connection.extend(Connection)
    end

    class Instrumenter
      attr_reader :configuration

      def initialize
        @configuration = Sentry.configuration
      end

      def instrument(op_name, env, &block)
        return unless Sentry.initialized?

        Sentry.with_child_span(op: op_name, start_timestamp: Sentry.utc_now.to_f, origin: SPAN_ORIGIN) do |sentry_span|
          request_info = extract_request_info(env)

          if propagate_trace?(request_info[:url])
            set_propagation_headers(env[:request_headers])
          end

          res = block.call

          if record_sentry_breadcrumb?
            record_sentry_breadcrumb(request_info, res)
          end

          if sentry_span
            sentry_span.set_description("#{request_info[:method]} #{request_info[:url]}")
            sentry_span.set_data(Span::DataConventions::URL, request_info[:url])
            sentry_span.set_data(Span::DataConventions::HTTP_METHOD, request_info[:method])
            sentry_span.set_data(Span::DataConventions::HTTP_QUERY, request_info[:query]) if request_info[:query]
            sentry_span.set_data(Span::DataConventions::HTTP_STATUS_CODE, res.status)
          end

          res
        end
      end

      private

      def extract_request_info(env)
        url = env[:url].scheme + "://" + env[:url].host + env[:url].path
        result = { method: env[:method].to_s.upcase, url: url }

        if configuration.send_default_pii
          result[:query] = env[:url].query
          result[:body] = env[:body]
        end

        result
      end

      def record_sentry_breadcrumb(request_info, res)
        crumb = Sentry::Breadcrumb.new(
          level: :info,
          category: BREADCRUMB_CATEGORY,
          type: :info,
          data: {
            status: res.status,
            **request_info
          }
        )

        Sentry.add_breadcrumb(crumb)
      end

      def record_sentry_breadcrumb?
        configuration.breadcrumbs_logger.include?(:http_logger)
      end

      def propagate_trace?(url)
        url &&
          configuration.propagate_traces &&
          configuration.trace_propagation_targets.any? { |target| url.match?(target) }
      end

      def set_propagation_headers(headers)
        Sentry.get_trace_propagation_headers&.each { |k, v| headers[k] = v }
      end
    end
  end
end
