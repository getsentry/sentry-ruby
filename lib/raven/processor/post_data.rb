module Raven
  class Processor::PostData < Processor
    def process(data)
      if data[:request] && data[:request][:method] == "POST"
        data[:request][:data] = nil # Remove possibly sensitive POST data
      end

      data
    end
  end
end
