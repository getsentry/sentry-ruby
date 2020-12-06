module Raven
  module Breadcrumbs
    module ActiveSupportLogger
      class << self
        def add(name, started, _finished, _unique_id, data)
          Raven.breadcrumbs.record do |crumb|
            crumb.data = data
            crumb.category = name
            crumb.timestamp = started.to_i
          end
        end

        def inject
          @subscriber = ::ActiveSupport::Notifications.subscribe(/.*/) do |name, started, finished, unique_id, data|
            add(name, started, finished, unique_id, data)
          end
        end

        def detach
          ::ActiveSupport::Notifications.unsubscribe(@subscriber)
        end
      end
    end
  end
end
