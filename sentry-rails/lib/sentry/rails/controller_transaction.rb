# frozen_string_literal: true

require "sentry/utils/http_tracing"

module Sentry
  module Rails
    module ControllerTransaction
      SPAN_ORIGIN = "auto.view.rails"

      def self.included(base)
        base.prepend_around_action(:sentry_around_action)
      end

      private

      def sentry_around_action
        if Sentry.initialized?
          transaction_name = "#{self.class}##{action_name}"
          Sentry.get_current_scope.set_transaction_name(transaction_name, source: :view)
          Sentry.with_child_span(op: "view.process_action.action_controller", description: transaction_name, origin: SPAN_ORIGIN) do |child_span|
            if child_span
              begin
                result = yield
              ensure
                child_span.set_http_status(response.status)
                child_span.set_data(:format, request.format)
                child_span.set_data(:method, request.method)

                data_collection = Sentry.configuration.data_collection

                path = request.path
                query_parameters = request.query_parameters

                if query_parameters.is_a?(Hash)
                  filtered_query_parameters = data_collection.url_query_params.filter(query_parameters)

                  unless filtered_query_parameters.empty?
                    formatted_query = Sentry::Utils::HttpTracing.format_query(filtered_query_parameters)
                    path = "#{path}?#{formatted_query}"
                  end
                end

                child_span.set_data(:path, path)

                # all params request + body
                params = request.params
                if params.is_a?(Hash)
                  filtered_params = data_collection.url_query_params.filter(params)
                  child_span.set_data(:params, filtered_params)
                end
              end

              result
            else
              yield
            end
          end
        else
          yield
        end
      end
    end
  end
end
