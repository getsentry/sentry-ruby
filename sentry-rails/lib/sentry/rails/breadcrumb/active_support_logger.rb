module Sentry
  module Rails
    module Breadcrumb
      module ActiveSupportLogger
        class << self
          IGNORED_DATA_TYPES = [:request, :headers, :exception, :exception_object]

          def add(name, started, _finished, _unique_id, data)
            if data.is_a?(Hash)
              # we should only mutate the copy of the data
              data = data.dup
              cleanup_data(data)
            end

            crumb = Sentry::Breadcrumb.new(
              data: data,
              category: name,
              timestamp: started.to_i
            )
            Sentry.add_breadcrumb(crumb)
          end

          def cleanup_data(data)
            IGNORED_DATA_TYPES.each do |key|
              data.delete(key) if data.key?(key)
            end
          end

          def inject
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
        end
      end
    end
  end
end
