# Encoding: utf-8

require 'spec_helper'

describe Raven::Processor::PutData do
  before do
    @client = double("client")
    @processor = described_class.new(@client)
  end

  it 'should remove put data when HTTP method is PUT' do
    data = {
      :request => {
        :method => "PUT",
        :data => {
          "sensitive_stuff" => "TOP_SECRET-GAMMA"
        }
      }
    }

    result = @processor.process(data)

    expect(result[:request][:data]).to eq("********")
  end

  it 'should NOT remove post data when HTTP method is not PUT' do
    data = {
      :request => {
        :method => "GET",
        :data => {
          "sensitive_stuff" => "TOP_SECRET-GAMMA"
        }
      }
    }

    result = @processor.process(data)

    expect(result[:request][:data]).to eq("sensitive_stuff" => "TOP_SECRET-GAMMA")
  end

  it 'should remove post data when HTTP method is PUT and keys are strings' do
    data = {
      "request" => {
        "method" => "PUT",
        "data" => {
          "sensitive_stuff" => "TOP_SECRET-GAMMA"
        }
      }
    }

    result = @processor.process(data)

    expect(result["request"]["data"]).to eq("********")
  end
end
