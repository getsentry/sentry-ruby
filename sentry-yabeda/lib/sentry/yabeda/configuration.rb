# frozen_string_literal: true

module Sentry
  class Configuration
    after(:configured) do
      Sentry::Yabeda.collector&.kill
      Sentry::Yabeda.collector = Sentry::Yabeda::Collector.new(self)
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
