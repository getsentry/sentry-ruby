require 'spec_helper'
require 'timecop'

RSpec.describe Raven::ClientState do
  let(:state) { Raven::ClientState.new }

  it 'should try when online' do
    expect(state.should_try?).to eq(true)
  end

  it 'should not try with a new error' do
    state.failure
    expect(state.should_try?).to eq(false)
  end

  it 'should try again after time passes' do
    Timecop.freeze(-10) { state.failure }
    expect(state.should_try?).to eq(true)
  end

  it 'should try again after success' do
    state.failure
    state.success
    expect(state.should_try?).to eq(true)
  end

  it 'should try again after retry_after' do
    Timecop.freeze(-2) { state.failure(1) }
    expect(state.should_try?).to eq(true)
  end

  it 'should exponentially backoff' do
    Timecop.freeze do
      state.failure
      Timecop.travel(2)
      expect(state.should_try?).to eq(true)

      state.failure
      Timecop.travel(3)
      expect(state.should_try?).to eq(false)
      Timecop.travel(2)
      expect(state.should_try?).to eq(true)

      state.failure
      Timecop.travel(8)
      expect(state.should_try?).to eq(false)
      Timecop.travel(2)
      expect(state.should_try?).to eq(true)
    end
  end
end
