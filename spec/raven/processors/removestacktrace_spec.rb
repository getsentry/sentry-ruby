require 'spec_helper'
require 'raven/processor/removestacktrace'

describe Raven::Processor::RemoveStacktrace do
  before do
    @client = double("client")
    allow(@client).to receive_message_chain(:configuration, :sanitize_fields) { [] }
    @processor = Raven::Processor::RemoveStacktrace.new(@client)
  end

  it 'should remove stacktraces' do
    data = Raven::Event.capture_exception(build_exception).to_hash

    expect(data['exception']['stacktrace']).to_not eq(nil)
    result = @processor.process(data)

    expect(result['exception']['stacktrace']).to eq(nil)
  end

end
