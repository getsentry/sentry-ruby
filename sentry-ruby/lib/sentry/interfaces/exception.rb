module Sentry
  class ExceptionInterface < Interface
    def initialize(values)
      @values = values
    end

    def to_hash
      data = super
      data[:values] = data[:values].map(&:to_hash) if data[:values]
      data
    end
  end
end
