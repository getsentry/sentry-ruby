require "spec_helper"

RSpec.describe Sentry::DelayedJob do
  before do
    perform_basic_setup
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end
end

