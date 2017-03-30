# Encoding: utf-8

require 'spec_helper'

describe Raven::Processor::PatchData do
  before do
    @client = double("client")
    @processor = described_class.new(@client)
  end

  it 'should remove put data when HTTP method is PATCH' do
    data = {
      :request => {
        :method => "PATCH",
        :data => {
          "sensitive_stuff" => "TOP_SECRET-GAMMA"
        }
      }
    }

    result = @processor.process(data)

    expect(result[:request][:data]).to eq("********")
  end

  it 'should NOT remove put data when HTTP method is not PATCH' do
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

  it 'should remove put data when HTTP method is PATCH and keys are strings' do
    data = {
      "request" => {
        "method" => "PATCH",
        "data" => {
          "sensitive_stuff" => "TOP_SECRET-GAMMA"
        }
      }
    }

    result = @processor.process(data)

    expect(result["request"]["data"]).to eq("********")
  end
end
