require 'spec_helper'
require 'raven/processor/removestacktrace'

RSpec.describe Raven::Processor::RemoveStacktrace do
  before do
    @client = double("client")
    @processor = Raven::Processor::RemoveStacktrace.new(@client)
  end

  it 'should remove stacktraces' do
    data = Raven.capture_exception(build_exception).to_hash

    expect(data[:exception][:values][0][:stacktrace]).to_not eq(nil)
    result = @processor.process(data)

    expect(result[:exception][:values][0][:stacktrace]).to eq(nil)
  end

  # Only check causes when they're supported
  if Exception.new.respond_to? :cause
    it 'should remove stacktraces from causes' do
      data = Raven.capture_exception(build_exception_with_cause).to_hash

      expect(data[:exception][:values][0][:stacktrace]).to_not eq(nil)
      expect(data[:exception][:values][1][:stacktrace]).to_not eq(nil)
      result = @processor.process(data)

      expect(result[:exception][:values][0][:stacktrace]).to eq(nil)
      expect(result[:exception][:values][1][:stacktrace]).to eq(nil)
    end

    it 'should remove stacktraces from nested causes' do
      data = Raven.capture_exception(build_exception_with_two_causes).to_hash

      expect(data[:exception][:values][0][:stacktrace]).to_not eq(nil)
      expect(data[:exception][:values][1][:stacktrace]).to_not eq(nil)
      expect(data[:exception][:values][2][:stacktrace]).to_not eq(nil)
      result = @processor.process(data)

      expect(result[:exception][:values][0][:stacktrace]).to eq(nil)
      expect(result[:exception][:values][1][:stacktrace]).to eq(nil)
      expect(result[:exception][:values][2][:stacktrace]).to eq(nil)
    end
  end

  if defined?(Rails) # depends on activesupport
    it 'should remove stacktraces even when keys are strings' do
      data = Raven.capture_exception(build_exception).to_hash.deep_stringify_keys

      expect(data["exception"]["values"][0]["stacktrace"]).to_not eq(nil)
      result = @processor.process(data)

      expect(result["exception"]["values"][0]["stacktrace"]).to eq(nil)
    end
  end
end
