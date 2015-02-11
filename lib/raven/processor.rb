require 'json'

module Raven
  class Processor
    attr_accessor :sanitize_fields

    def initialize(client)
      @client = client
      @sanitize_fields = client.configuration.sanitize_fields
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
