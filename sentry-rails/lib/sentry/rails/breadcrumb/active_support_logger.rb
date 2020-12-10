module Sentry
  module Rails
    module Breadcrumb
      module ActiveSupportLogger
        class << self
          def add(name, started, _finished, _unique_id, data)
            crumb = Sentry::Breadcrumb.new(
              data: data,
              category: name,
              timestamp: started.to_i
            )
            Sentry.add_breadcrumb(crumb)
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
