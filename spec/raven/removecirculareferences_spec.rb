# Encoding: utf-8

require 'spec_helper'

describe Raven::Processor::RemoveCircularReferences do
  before do
    @client = double("client")
    @processor = Raven::Processor::RemoveCircularReferences.new(@client)
  end

  it 'should cleanup circular references' do
    data = {}
    data['data'] = data
    data['ary'] = []
    data['ary'].push('x' => data['ary'])
    data['ary2'] = data['ary']

    result = @processor.process(data)
    expect(result['data']).to eq('(...)')
    expect(result['ary'].first['x']).to eq('(...)')
    expect(result['ary2']).not_to eq('(...)')
  end
end
