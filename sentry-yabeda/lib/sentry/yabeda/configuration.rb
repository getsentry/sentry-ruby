# frozen_string_literal: true

module Sentry
  class Configuration
    after(:configured) do
      if enable_metrics
        Sentry::Yabeda.collector&.kill
        Sentry::Yabeda.collector = Sentry::Yabeda::Collector.new(self)
      end
    end

    after(:closed) do
      if (collector = Sentry::Yabeda.collector)
        collector.run
        collector.kill
        Sentry::Yabeda.collector = nil
      end
    end
  end
end
