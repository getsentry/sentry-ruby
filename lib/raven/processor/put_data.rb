module Raven
  class Processor::PutData < Processor
    include RequestDataHelper

    def process(data)
      sanitize_request_data(data, "PUT")

      data
    end
  end
end
