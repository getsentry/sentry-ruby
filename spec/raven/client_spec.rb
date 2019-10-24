require 'spec_helper'

RSpec.describe Raven::Client do
  let(:configuration) do
    Raven::Configuration.new.tap do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
    end
  end
  let(:client) { Raven::Client.new(configuration) }

  before do
    @fake_time = Time.now
    allow(Time).to receive(:now).and_return @fake_time
  end

  it "generates an auth header" do
    expect(client.send(:generate_auth_header)).to eq(
      "Sentry sentry_version=5, sentry_client=raven-ruby/#{Raven::VERSION}, sentry_timestamp=#{@fake_time.to_i}, " \
      "sentry_key=12345, sentry_secret=67890"
    )
  end

  it "generates a message with exception" do
    event = Raven::CLI.test(Raven.configuration.server, true, Raven.configuration).to_hash
    expect(client.send(:get_message_from_exception, event)).to eq("ZeroDivisionError: divided by 0")
  end

  it "generates a message without exception" do
    event = Raven::Event.from_message("this is an STDOUT transport test").to_hash
    expect(client.send(:get_message_from_exception, event)).to eq(nil)
  end

  it "generates an auth header without a secret (Sentry 9)" do
    client.configuration.server = "https://66260460f09b5940498e24bb7ce093a0@sentry.io/42"

    expect(client.send(:generate_auth_header)).to eq(
      "Sentry sentry_version=5, sentry_client=raven-ruby/#{Raven::VERSION}, sentry_timestamp=#{@fake_time.to_i}, " \
      "sentry_key=66260460f09b5940498e24bb7ce093a0"
    )
  end
end
