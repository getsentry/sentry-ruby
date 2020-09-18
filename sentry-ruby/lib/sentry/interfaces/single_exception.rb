module Sentry
  class SingleExceptionInterface < Interface
    attr_accessor :type
    attr_accessor :value
    attr_accessor :module
    attr_accessor :stacktrace

    def to_hash(*args)
      data = super(*args)
      data[:stacktrace] = data[:stacktrace].to_hash if data[:stacktrace]
      data
    end
  end
end
