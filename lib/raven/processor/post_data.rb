module Raven
  class Processor::PostData < Processor
    def process(data)
      if data[:request] && data[:request][:method] == "POST"
        data[:request][:data] = STRING_MASK # Remove possibly sensitive POST data
      end

      data
    end
  end
end
