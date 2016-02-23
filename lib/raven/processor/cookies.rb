module Raven
  class Processor::Cookies < Processor
    def process(data)
      if data[:request]
        # Remove possibly sensitive cookies
        data[:request][:cookies] = nil if data[:request][:cookies]

        if data[:request][:headers] && data[:request][:headers]["Cookie"]
          data[:request][:headers]["Cookie"] = nil
        end
      end

      data
    end
  end
end
