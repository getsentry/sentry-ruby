require 'test_helper'

class RavenClientStateTest < Raven::Test
  def setup
    @state = Raven::ClientState.new
  end

  it 'should try when online' do
    assert @state.should_try?
  end

  it 'should not try with a new error' do
    @state.failure
    refute @state.should_try?
  end

  it 'should try again after success' do
    @state.failure
    @state.success

    assert @state.should_try?
  end
end

class RavenClientStateTimeTest < Raven::ThreadUnsafeTest
  def setup
    @state = Raven::ClientState.new
  end

  it 'should try again after time passes' do
    Time.stub(:now, Time.now - 10) { @state.failure }

    assert @state.should_try?
  end

  it 'should try again after retry_after' do
    Time.stub(:now, Time.now - 2) { @state.failure(1) }

    assert @state.should_try?
  end

  it 'should exponentially backoff' do
    time = Time.now
    Time.stub(:now, time)     { @state.failure }
    Time.stub(:now, time + 2) { assert @state.should_try? }

    Time.stub(:now, time + 2) { @state.failure }
    Time.stub(:now, time + 5) { refute @state.should_try? }
    Time.stub(:now, time + 7) { assert @state.should_try? }

    Time.stub(:now, time + 7)  { @state.failure }
    Time.stub(:now, time + 15) { refute @state.should_try? }
    Time.stub(:now, time + 17) { assert @state.should_try? }
  end
end
