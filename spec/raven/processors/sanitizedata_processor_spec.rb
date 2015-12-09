require 'spec_helper'

describe Raven::Processor::SanitizeData do
  before do
    @client = double("client")
    allow(@client).to receive_message_chain(:configuration, :sanitize_fields) { ['user_field'] }
    allow(@client).to receive_message_chain(:configuration, :sanitize_credit_cards) { true }
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
          :ssn => '123-45-6789', # test symbol handling
          'social_security_number' => 123456789,
          'user_field' => 'user',
          'user_field_foo' => 'hello'
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
    expect(vars[:ssn]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["social_security_number"]).to eq(Raven::Processor::SanitizeData::INT_MASK)
    expect(vars["user_field"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["user_field_foo"]).to eq('hello')
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
        'social_security_number' => 123456789,
        'user_field' => 'user',
        'user_field_foo' => 'hello'
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
    expect(vars["user_field"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(vars["user_field_foo"]).to eq('hello')
  end

  it 'should filter json embedded in a ruby object' do
    data_with_embedded_json = {
      'data' => {
        'json' => %w(foo bar).to_json,
        'json_hash' => {'foo' => 'bar'}.to_json,
        'sensitive' => {'password' => 'secret'}.to_json
        }
      }

    result = @processor.process(data_with_embedded_json)

    expect(JSON.parse(result["data"]["json"])).to eq(%w(foo bar))
    expect(JSON.parse(result["data"]["json_hash"])).to eq('foo' => 'bar')
    expect(JSON.parse(result["data"]["sensitive"])).to eq('password' => Raven::Processor::SanitizeData::STRING_MASK)
  end

  it 'should not fail when json is invalid' do
    data_with_invalid_json = {
      'data' => {
          'invalid' => "{\r\n\"key\":\"value\",\r\n \"foo\":{\"bar\":\"baz\"}\r\n"
        }
      }

    result = @processor.process(data_with_invalid_json)

    expect{JSON.parse(result["data"]["invalid"])}.to raise_exception(JSON::ParserError)
  end

  it 'should filter credit card values' do
    data = {
      'ccnumba' => '4242424242424242',
      'ccnumba_13' => '4242424242424',
      'ccnumba-dash' => '4242-4242-4242-4242',
      'ccnumba_int' => 4242424242424242,
    }

    result = @processor.process(data)
    expect(result["ccnumba"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(result["ccnumba_13"]).to eq(Raven::Processor::SanitizeData::STRING_MASK)
    expect(result["ccnumba_int"]).to eq(Raven::Processor::SanitizeData::INT_MASK)
  end

  it 'should pass through credit card values if configured' do
    @processor.sanitize_credit_cards = false
    data = {
      'ccnumba' => '4242424242424242',
      'ccnumba_13' => '4242424242424',
      'ccnumba-dash' => '4242-4242-4242-4242',
      'ccnumba_int' => 4242424242424242,
    }

    result = @processor.process(data)
    expect(result["ccnumba"]).to eq('4242424242424242')
    expect(result["ccnumba_13"]).to eq('4242424242424')
    expect(result["ccnumba_int"]).to eq(4242424242424242)
  end

  it 'sanitizes hashes nested in arrays' do
    data = {
      "empty_array"=> [],
      "array"=>[{'password' => 'secret'}],
    }

    result = @processor.process(data)

    expect(result["array"][0]['password']).to eq(Raven::Processor::SanitizeData::STRING_MASK)
  end

  context "query strings" do
    it 'sanitizes' do
      data = {
        'sentry.interfaces.Http' => {
          'data' => {
            'query_string' => 'foo=bar&password=secret'
          }
        }
      }

      result = @processor.process(data)

      vars = result["sentry.interfaces.Http"]["data"]
      expect(vars["query_string"]).to_not include("secret")
    end

    it 'handles :query_string as symbol' do
      data = {
        'sentry.interfaces.Http' => {
          'data' => {
            :query_string => 'foo=bar&password=secret'
          }
        }
      }

      result = @processor.process(data)

      vars = result["sentry.interfaces.Http"]["data"]
      expect(vars[:query_string]).to_not include("secret")
    end

    it 'handles multiple values for a key' do
      data = {
        'sentry.interfaces.Http' => {
          'data' => {
            'query_string' => 'foo=bar&foo=fubar&foo=barfoo'
          }
        }
      }

      result = @processor.process(data)

      vars = result["sentry.interfaces.Http"]["data"]
      query_string = vars["query_string"].split('&')
      expect(query_string).to include("foo=bar")
      expect(query_string).to include("foo=fubar")
      expect(query_string).to include("foo=barfoo")
    end

    it 'handles url encoded keys and values' do
      encoded_query_string = 'Bio+4%24=cA%24%7C-%7C+M%28%29n3%5E'
      data = {
        'sentry.interfaces.Http' => {
          'data' => {
            'query_string' => encoded_query_string
          }
        }
      }

      result = @processor.process(data)

      vars = result["sentry.interfaces.Http"]["data"]
      expect(vars["query_string"]).to eq(encoded_query_string)
    end

    it 'handles url encoded values' do

    end
  end
end
