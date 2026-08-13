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
                query = data_collection.url_query_params.filter(request.query_parameters)
                path = request.path
                path = "#{path}?#{Sentry::Utils::HttpTracing.format_query(query)}" unless query.empty?

                child_span.set_data(:path, path)
                child_span.set_data(
                  :params,
                  data_collection.url_query_params.filter(request.params)
                )
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
