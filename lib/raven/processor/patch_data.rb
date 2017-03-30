module Raven
  class Processor::PatchData < Processor
    include RequestDataHelper

    def process(data)
      sanitize_request_data(data, "PATCH")

      data
    end
  end
end
