module Raven
  module RubyJson
    def self.error_class
      JSON::JSONError
    end

    def self.encode(data)
      JSON.generate(data)
    end

    def self.decode(str)
      JSON.parse(str)
    end
  end
end
