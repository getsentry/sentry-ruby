require 'spec_helper'

RSpec.describe Raven::Processor::RemoveCircularReferences do
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
    data['leave intact'] = { 'not a circular reference' => true }

    result = @processor.process(data)
    expect(result['data']).to eq('(...)')
    expect(result['ary'].first['x']).to eq('(...)')
    expect(result['ary2']).to eq("(...)")
    expect(result['leave intact']).to eq('not a circular reference' => true)
  end
end
