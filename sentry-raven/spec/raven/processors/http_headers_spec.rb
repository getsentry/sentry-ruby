require 'spec_helper'

RSpec.describe Raven::Processor::HTTPHeaders do
  before do
    @client = double("client")
    allow(@client).to receive_message_chain(:configuration, :sanitize_http_headers) { ['User-Defined-Header'] }
    @processor = Raven::Processor::HTTPHeaders.new(@client)
  end

  it 'should remove HTTP headers we dont like' do
    data = {
      :request => {
        :headers => {
          "Authorization" => "dontseeme",
          "AnotherHeader" => "still_here"
        }
      }
    }

    result = @processor.process(data)

    expect(result[:request][:headers]["Authorization"]).to eq("********")
    expect(result[:request][:headers]["AnotherHeader"]).to eq("still_here")
  end

  it 'should be configurable' do
    data = {
      :request => {
        :headers => {
          "User-Defined-Header" => "dontseeme",
          "AnotherHeader" => "still_here"
        }
      }
    }

    result = @processor.process(data)

    expect(result[:request][:headers]["User-Defined-Header"]).to eq("********")
    expect(result[:request][:headers]["AnotherHeader"]).to eq("still_here")
  end

  it "should remove headers even if the keys are strings" do
    data = {
      "request" => {
        "headers" => {
          "Authorization" => "dontseeme",
          "AnotherHeader" => "still_here"
        }
      }
    }

    result = @processor.process(data)

    expect(result["request"]["headers"]["Authorization"]).to eq("********")
    expect(result["request"]["headers"]["AnotherHeader"]).to eq("still_here")
  end
end
