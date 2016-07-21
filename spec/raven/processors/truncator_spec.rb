require 'spec_helper'

describe Raven::Processor::Truncator do
  before do
    @client = double("client")
    allow(@client).to receive_message_chain(:configuration, :event_bytesize_limit) { 8_000 }
    @processor = Raven::Processor::Truncator.new(@client)
  end

  it 'should truncate strings longer than configured' do
    data = {
      :request_body => "a" * 16_000
    }

    result = @processor.process(data)

    expect(result[:request_body].bytesize).to eq(@client.configuration.event_bytesize_limit)
  end
end
