require 'spec_helper'

RSpec.describe Sentry::Transports::Stdout do
  let(:config) { Sentry::Configuration.new.tap { |c| c.dsn = 'stdout://12345:67890@sentry.localdomain/sentry/42' } }
  let(:client) { Sentry::Client.new(config) }
  subject { described_class.new(config) }

  it 'should write to stdout' do
    event = JSON.generate(client.event_from_message("this is an STDOUT transport test").to_hash)
    expect { subject.send_data(event) }.to output(/\"message\":\"this is an STDOUT transport test\"/).to_stdout
  end
end
