# Encoding: utf-8

require 'spec_helper'

describe Raven::Processor::UTF8Conversion do
  before do
    @client = double("client")
    @processor = Raven::Processor::UTF8Conversion.new(@client)
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

    it 'should work recursively on hashes' do
      data = {'nested' => {}}
      data['nested']['invalid'] = "invalid utf8 string goes here\255".force_encoding('UTF-8')

      results = @processor.process(data)
      expect(results['nested']['invalid']).to eq("invalid utf8 string goes here")
    end

    it 'should work recursively on arrays' do
      data = ['good string', 'good string',
        ['good string', "invalid utf8 string goes here\255".force_encoding('UTF-8')]]

      results = @processor.process(data)
      expect(results[2][1]).to eq("invalid utf8 string goes here")
    end

    it 'should not blow up on symbols' do
      data = {:key => :value}

      results = @processor.process(data)
      expect(results[:key]).to eq(:value)
    end
  end
end
