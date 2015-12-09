module Raven
  class Processor
    def initialize(client)
      @client = client
    end

    def process(data)
      fail NotImplementedError
    end
  end
end
