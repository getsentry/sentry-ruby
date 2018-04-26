require 'spec_helper'

RSpec.describe Raven::Transports::Stdout do
  let(:config) { Raven::Configuration.new.tap { |c| c.dsn = 'stdout://12345:67890@sentry.localdomain/sentry/42' } }
  let(:client) { Raven::Client.new(config) }

  it 'should write to stdout' do
    event = JSON.generate(Raven::Event.from_message("stdout test").to_hash)
    expect { client.send(:transport).send_event("test", event) }.not_to raise_error
  end
end
