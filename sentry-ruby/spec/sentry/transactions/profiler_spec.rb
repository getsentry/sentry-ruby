# frozen_string_literal: true

require 'contexts/with_request_mock'

RSpec.describe Sentry, 'transactions / profiler', when: [:vernier_installed?, :rack_available?] do
  include_context "with request mock"

  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
      config.profiles_sample_rate = 1.0
      config.profiler_class = Sentry::Vernier::Profiler
    end
  end

  it 'starts profiler just once inside nested transactions' do
    10.times do
      parent_transaction = Sentry.start_transaction(name: "parent")
      nested_transaction = Sentry.start_transaction(name: "nested")

      ProfilerTest::Bar.bar

      expect(Sentry.get_current_hub.profiler_running?).to be(true)

      expect(parent_transaction.profiler).to_not be_nil
      expect(nested_transaction.profiler).to be_nil

      nested_transaction.finish
      parent_transaction.finish
    end
  end
end
