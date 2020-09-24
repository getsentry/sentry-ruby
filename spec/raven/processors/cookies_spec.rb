require 'spec_helper'

RSpec.describe Raven::Processor::Cookies do
  before do
    @client = double("client")
    @processor = Raven::Processor::Cookies.new(@client)
  end

  it 'should remove cookies' do
    test_data = {
      :request => {
        :headers => {
          "Cookie" => { "_sentry-testapp_session" => "SlRKVnNha2Z" },
          "AnotherHeader" => "still_here"
        },
        :cookies => { "_sentry-testapp_session" => "SlRKVnNha2Z" },
        :some_other_data => "still_here"
      }
    }

    result = @processor.process(test_data)

    expect(result[:request][:cookies]).to eq({ "_sentry-testapp_session" => "********" })
    expect(result[:request][:headers]["Cookie"]).to eq({ "_sentry-testapp_session" => "********" })
    expect(result[:request][:some_other_data]).to eq("still_here")
    expect(result[:request][:headers]["AnotherHeader"]).to eq("still_here")
  end

  it 'should remove cookies even if keys are strings' do
    test_data = {
      "request" => {
        "headers" => {
          "Cookie" => { "_sentry-testapp_session" => "SlRKVnNha2Z" },
          "AnotherHeader" => "still_here"
        },
        "cookies" => { "_sentry-testapp_session" => "SlRKVnNha2Z" },
        "some_other_data" => "still_here"
      }
    }

    result = @processor.process(test_data)

    expect(result["request"]["cookies"]).to eq({ "_sentry-testapp_session" => "********" })
    expect(result["request"]["headers"]["Cookie"]).to eq({ "_sentry-testapp_session" => "********" })
    expect(result["request"]["some_other_data"]).to eq("still_here")
    expect(result["request"]["headers"]["AnotherHeader"]).to eq("still_here")
  end

  it 'does not fail if it runs after Processor::RemoveCircularReferences' do
    test_data = {
      :request => {
        :headers => {
          "Cookie" => Raven::Processor::RemoveCircularReferences::ELISION_STRING,
          "AnotherHeader" => "still_here"
        },
        :cookies => Raven::Processor::RemoveCircularReferences::ELISION_STRING,
        :some_other_data => "still_here"
      }
    }

    @processor.process(test_data)
  end
end
