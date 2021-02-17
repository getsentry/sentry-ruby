module Sentry
  class SingleExceptionInterface < Interface
    attr_accessor :type
    attr_accessor :value
    attr_accessor :module
    attr_accessor :thread_id
    attr_accessor :stacktrace

    def to_hash
      data = super
      data[:stacktrace] = data[:stacktrace].to_hash if data[:stacktrace]
      data
    end
  end
end
