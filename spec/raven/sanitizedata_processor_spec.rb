require File.expand_path('../../spec_helper', __FILE__)
require 'raven/processors/sanitizedata'

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
    data = {
      'foo' => 'bar',
      'password' => 'hello',
      'the_secret' => 'hello',
      'a_password_here' => 'hello',
      'mypasswd' => 'hello',
      'test' => 1,
      'ssn' => '123-45-6789',
      'social_security_number' => 123456789
    }.to_json

    result = JSON.parse(@processor.process(data))

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

  it 'should cleanup circular dependendencies' do
    data = {}
    data['data'] = data
    data['ary'] = []
    data['ary'].push('x' => data['ary'])
    data['ary2'] = data['ary']

    result = @processor.process(data)
    expect(result['data']).to eq('{...}')
    expect(result['ary'].first['x']).to eq('[...]')
    expect(result['ary2']).not_to eq('[...]')
  end

  if RUBY_VERSION > '1.8.7'
    it 'should not fail because of invalid byte sequence in UTF-8' do
      data = {}
      data['invalid'] = "invalid utf8 string goes here\255".force_encoding('UTF-8')

      expect { @processor.process(data) }.not_to raise_error
    end

    it 'should cleanup invalid UTF-8 bytes' do
      data = {}
      data['invalid'] = "invalid utf8 string goes here\255".force_encoding('UTF-8')

      results = @processor.process(data)
      expect(results['invalid']).to eq("invalid utf8 string goes here")
    end

    it 'should keep valid UTF-8 bytes after cleaning' do
      data = {}
      data['invalid'] = "한국, 中國, 日本(にっぽん)\255".force_encoding('UTF-8')

      results = @processor.process(data)
      expect(results['invalid']).to eq("한국, 中國, 日本(にっぽん)")
    end
  end

end
