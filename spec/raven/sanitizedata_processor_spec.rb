require File::expand_path('../../spec_helper', __FILE__)
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
        }
      }
    }

    result = @processor.process(data)

    vars = result["sentry.interfaces.Http"]["data"]
    vars["foo"].should eq("bar")
    vars["password"].should eq(Raven::Processor::SanitizeData::MASK)
    vars["the_secret"].should eq(Raven::Processor::SanitizeData::MASK)
    vars["a_password_here"].should eq(Raven::Processor::SanitizeData::MASK)
    vars["mypasswd"].should eq(Raven::Processor::SanitizeData::MASK)
  end

  it 'should filter credit card values' do
    data = {
      'ccnumba' => '4242424242424242'
    }

    result = @processor.process(data)
    result["ccnumba"].should eq(Raven::Processor::SanitizeData::MASK)
  end

end
