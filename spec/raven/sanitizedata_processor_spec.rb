require 'spec_helper'

describe Raven::Processor::SanitizeData do
  before do
    @client = double("client")
    @processor = Raven::Processor::SanitizeData.new(@client)
  end

  it 'should filter http data' do
    data = {
      'sentry.interfaces.Http' => {
        'data' => {
          'foo' => 'bar',
          'password' => 'hello',
          'the_secret' => 'hello',
          'a_password_here' => 'hello',
          'mypasswd' => 'hello',
          'test' => 1,
          'ssn' => '123-45-6789',
          'social_security_number' => 123456789
        }
      }
    }

    result = @processor.process(data)

    vars = result["sentry.interfaces.Http"]["data"]
    expect(vars["foo"]).to eq("bar")
    expect(vars["password"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["the_secret"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["a_password_here"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["mypasswd"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["test"]).to eq(1)
    expect(vars["ssn"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["social_security_number"]).to eq(Raven::Processor::SanitizeData::INT_MASK)
  end

  it 'should filter json data' do
    data_with_json = {
      'json' => {
        'foo' => 'bar',
        'password' => 'hello',
        'the_secret' => 'hello',
        'a_password_here' => 'hello',
        'mypasswd' => 'hello',
        'test' => 1,
        'ssn' => '123-45-6789',
        'social_security_number' => 123456789
        }.to_json
      }

    result = JSON.parse(@processor.process(data_with_json)['json'])

    vars = result
    expect(vars["foo"]).to eq("bar")
    expect(vars["password"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["the_secret"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["a_password_here"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["mypasswd"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["test"]).to eq(1)
    expect(vars["ssn"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["social_security_number"]).to eq(Raven::Processor::SanitizeData::INT_MASK)
  end

  it 'should filter credit card values' do
    data = {
      'ccnumba' => '4242424242424242',
      'ccnumba_int' => 4242424242424242,
    }

    result = @processor.process(data)
    expect(result["ccnumba"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(result["ccnumba_int"]).to eq(Raven::Processor::SanitizeData::INT_MASK)
  end

end
