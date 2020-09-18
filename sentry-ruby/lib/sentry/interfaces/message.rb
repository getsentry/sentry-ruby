module Sentry
  class MessageInterface < Interface
    attr_accessor :message, :params

    def initialize(*arguments)
      self.params = []
      super(*arguments)
    end

    def unformatted_message
      Array(params).empty? ? message : message % params
    end

    def self.sentry_alias
      :logentry
    end
  end
end
