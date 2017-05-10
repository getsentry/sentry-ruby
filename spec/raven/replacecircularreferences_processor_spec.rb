require File::expand_path('../../spec_helper', __FILE__)
require 'raven/processors/replacecircularreferences'

describe Raven::Processor::ReplaceCircularReferences do
  before do
    @client = double("client")
    @processor = Raven::Processor::ReplaceCircularReferences.new(@client)
  end

  it 'should replace circular references with "<...>"' do
    circular = {}
    circular['circular'] = circular
    data = {
      'sentry.interfaces.Http' => {
        'data' => circular
      }
    }

    result = @processor.process(data)

    vars = result["sentry.interfaces.Http"]["data"]
    vars["circular"].should eq("<...>")
  end

end
