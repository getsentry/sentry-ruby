# frozen_string_literal: true

module Sentry
  module Utils
    module HttpTracing
      def set_span_info(sentry_span, request_info, response_status)
        sentry_span.set_description("#{request_info[:method]} #{request_info[:url]}")
        sentry_span.set_data(Span::DataConventions::URL, request_info[:url])
        sentry_span.set_data(Span::DataConventions::HTTP_METHOD, request_info[:method])
        sentry_span.set_data(Span::DataConventions::HTTP_QUERY, request_info[:query]) if request_info[:query]
        sentry_span.set_data(Span::DataConventions::HTTP_STATUS_CODE, response_status)
      end

      def set_propagation_headers(req)
        Sentry.get_trace_propagation_headers&.each do |k, v|
          if k == BAGGAGE_HEADER_NAME && req[k]
            # Use Baggage.serialize_with_third_party to respect W3C limits
            # Get the baggage object directly to avoid parse-serialize round-trip
            scope = Sentry.get_current_scope
            baggage = scope&.get_span&.transaction&.get_baggage || scope&.propagation_context&.get_baggage

            if baggage
              req[k] = Baggage.serialize_with_third_party(baggage.items, req[k])
            else
              # Fallback to preserve third-party baggage if baggage object is unavailable
              req[k] = "#{v},#{req[k]}"
            end
          else
            req[k] = v
          end
        end
      end

      def record_sentry_breadcrumb(request_info, response_status)
        crumb = Sentry::Breadcrumb.new(
          level: get_level(response_status),
          category: self.class::BREADCRUMB_CATEGORY,
          type: "info",
          data: { status: response_status, **request_info }
        )

        Sentry.add_breadcrumb(crumb)
      end

      def record_sentry_breadcrumb?
        Sentry.initialized? && Sentry.configuration.breadcrumbs_logger.include?(:http_logger)
      end

      def propagate_trace?(url)
        url &&
          Sentry.initialized? &&
          Sentry.configuration.propagate_traces &&
          Sentry.configuration.trace_propagation_targets.any? { |target| url.match?(target) }
      end

      # Kindly borrowed from Rack::Utils
      def build_nested_query(value, prefix = nil)
        case value
        when Array
          value.map { |v|
            build_nested_query(v, "#{prefix}[]")
          }.join("&")
        when Hash
          value.map { |k, v|
            build_nested_query(v, prefix ? "#{prefix}[#{k}]" : k)
          }.delete_if(&:empty?).join("&")
        when nil
          URI.encode_www_form_component(prefix)
        else
          raise ArgumentError, "value must be a Hash" if prefix.nil?
          "#{URI.encode_www_form_component(prefix)}=#{URI.encode_www_form_component(value)}"
        end
      end

      private

      def get_level(status)
        return :info unless status && status.is_a?(Integer)

if status >= 500
  :error
elsif status >= 400
  :warning
else
  :info
end
      end
    end
  end
end
