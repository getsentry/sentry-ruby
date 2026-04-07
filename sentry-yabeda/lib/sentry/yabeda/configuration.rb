# frozen_string_literal: true

module Sentry
  class Configuration
    after(:configured) do
      if enable_metrics
        Sentry::Yabeda.collector&.kill
        Sentry::Yabeda.collector = Sentry::Yabeda::Collector.new(self)
      end
    end
  end
end
