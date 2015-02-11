require 'json'

module Raven
  class Processor
    def initialize(client)
      @client = client
    end

    def process(data)
      data
    end

    private

    def parse_json_or_nil(string)
      begin
        OkJson.decode(string)
      rescue Raven::OkJson::Error, NoMethodError
        nil
      end
    end
  end
end
