require 'spec_helper'

RSpec.describe Raven::Processor::UTF8Conversion do
  before do
    @client = double("client")
    @processor = Raven::Processor::UTF8Conversion.new(@client)
    @bad_utf8_string = "invalid utf8 string goes here\255".dup.force_encoding('UTF-8')
  end

  it "has a utf8 fixture which is not valid utf-8" do
    expect(@bad_utf8_string.valid_encoding?).to eq(false)
    expect { @bad_utf8_string.match("") }.to raise_error(ArgumentError)
  end

  it 'should cleanup invalid UTF-8 bytes' do
    data = {}
    data['invalid'] = @bad_utf8_string

    results = @processor.process(data)
    expect(results['invalid']).to eq("invalid utf8 string goes here")
  end

  it "should cleanup invalid UTF-8 bytes in Exception messages" do
    data = Exception.new(@bad_utf8_string)

    results = @processor.process(data)
    expect(results.message).to eq("invalid utf8 string goes here")
  end

  it 'should keep valid UTF-8 bytes after cleaning' do
    data = {}
    data['invalid'] = "한국, 中國, 日本(にっぽん)\255".dup.force_encoding('UTF-8')

    results = @processor.process(data)
    expect(results['invalid']).to eq("한국, 中國, 日本(にっぽん)")
  end

  it 'should work recursively on hashes' do
    data = { 'nested' => {} }
    data['nested']['invalid'] = @bad_utf8_string

    results = @processor.process(data)
    expect(results['nested']['invalid']).to eq("invalid utf8 string goes here")
  end

  it 'should work recursively on arrays' do
    data = ['good string', 'good string',
            ['good string', @bad_utf8_string]]

    results = @processor.process(data)
    expect(results[2][1]).to eq("invalid utf8 string goes here")
  end

  it 'should not blow up on symbols' do
    data = { :key => :value }

    results = @processor.process(data)
    expect(results[:key]).to eq(:value)
  end

  it "deals with unicode hidden in ASCII_8BIT" do
    data = ["\xE2\x9C\x89 Hello".dup.force_encoding(Encoding::ASCII_8BIT)]

    results = @processor.process(data)

    # Calling JSON.generate here to simulate this value eventually being fed
    # to JSON generator in the client for transport, we're looking to see
    # if encoding errors are raised
    expect(JSON.generate(results)).to eq("[\"✉ Hello\"]")
  end

  it "deals with unicode hidden in ASCII_8BIT when the string is frozen" do
    data = ["\xE2\x9C\x89 Hello".dup.force_encoding(Encoding::ASCII_8BIT).freeze]

    results = @processor.process(data)

    expect(JSON.generate(results)).to eq("[\"✉ Hello\"]")
  end
end
