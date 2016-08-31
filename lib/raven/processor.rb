module Raven
  class Processor
    STRING_MASK = '********'.freeze
    INT_MASK = 0
    REGEX_SPECIAL_CHARACTERS = %w(. $ ^ { [ ( | ) * + ?).freeze

    def initialize(client)
      @client = client
    end

    def process(_data)
      raise NotImplementedError
    end
  end
end
