# frozen_string_literal: true

require "sentry/utils/http_tracing"

module Sentry
  module Rails
    module Breadcrumb
      module ActiveSupportLogger
        class << self
          include Sentry::Utils::HttpTracing
          def add(name, started, _finished, _unique_id, data)
            return unless Sentry.initialized?

            # skip Rails' internal events
            return if name.start_with?("!")

            if data.is_a?(Hash)
              data = data.slice(*@allowed_keys[name])
              filter_data_collection!(data)
            end

            crumb = Sentry::Breadcrumb.new(
              data: data,
              category: name,
              timestamp: started.to_i
            )
            Sentry.add_breadcrumb(crumb)
          end

          def inject(allowed_keys)
            @allowed_keys = allowed_keys

            @subscriber = ::ActiveSupport::Notifications.subscribe(/.*/) do |name, started, finished, unique_id, data|
              # we only record events that has a started timestamp
              if started.is_a?(Time)
                add(name, started, finished, unique_id, data)
              end
            end
          end

          def detach
            ::ActiveSupport::Notifications.unsubscribe(@subscriber)
          end

          private

          def filter_data_collection!(data)
            filter_params!(data)
            filter_path!(data)
          end

          def filter_params!(data)
            return unless data.key?(:params) && data[:params].is_a?(Hash)

            data[:params] = Sentry.configuration.data_collection.url_query_params.filter(data[:params])
            data.delete(:params) if data[:params].empty?
          end

          def filter_path!(data)
            return unless data.key?(:path) && data[:path].is_a?(String)

            path, query = data[:path].split("?", 2)
            return unless query

            filtered_query = filter_query_params(query)
            data[:path] = filtered_query ? "#{path}?#{filtered_query}" : path
          end
        end
      end
    end
  end
end
