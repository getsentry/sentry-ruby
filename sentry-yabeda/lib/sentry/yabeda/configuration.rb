# frozen_string_literal: true

module Sentry
  class Configuration
    after(:configured) do
      Sentry::Yabeda.collector&.kill
      Sentry::Yabeda.collector = nil

      if enable_metrics
        Sentry::Yabeda.collector = Sentry::Yabeda::Collector.new(self)
      end
    end
  end
end
