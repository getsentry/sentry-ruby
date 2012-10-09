module Raven

  module Processor
    class Processor
      def initialize(client)
        @client = client
      end

      def process(data)
        data
      end
    end
  end

end
