module Raven
  class Processor::Cookies < Processor
    def process(data)
      if data[:request]
        # Remove possibly sensitive cookies
        data[:request][:cookies] = STRING_MASK if data[:request][:cookies]

        if data[:request][:headers] && data[:request][:headers]["Cookie"]
          data[:request][:headers]["Cookie"] = STRING_MASK
        end
      end

      data
    end
  end
end
