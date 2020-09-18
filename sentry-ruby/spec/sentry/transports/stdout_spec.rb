require 'spec_helper'

RSpec.describe Sentry::Transports::Stdout do
  let(:config) { Sentry::Configuration.new.tap { |c| c.dsn = 'stdout://12345:67890@sentry.localdomain/sentry/42' } }
  let(:client) { Sentry::Client.new(config) }

  it 'should write to stdout' do
    event = JSON.generate(Sentry.capture_message("this is an STDOUT transport test").to_hash)
    expect { client.send(:transport).send_event("stdout test", event) }.to output(/\"message\":\"this is an STDOUT transport test\"/).to_stdout
  end
end
