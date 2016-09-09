describe Raven::Transports::HTTP do
  before do
    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
    end
  end

  it 'should set a custom User-Agent' do
    expect(Raven.client.send(:transport).conn.headers[:user_agent]).to eq("sentry-ruby/#{Raven::VERSION}")
  end

  it 'should raise an error on 4xx responses' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [404, {}, 'not found'] }
    end
    Raven.configure { |config| config.http_adapter = [:test, stubs] }

    event = JSON.generate(Raven::Event.from_message("test").to_hash)
    expect { Raven.client.send(:transport).send_event("test", event) }.to raise_error(Faraday::ResourceNotFound)

    stubs.verify_stubbed_calls
  end

  it 'should raise an error on 5xx responses' do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('sentry/api/42/store/') { [500, {}, 'error'] }
    end
    Raven.configure { |config| config.http_adapter = [:test, stubs] }

    event = JSON.generate(Raven::Event.from_message("test").to_hash)
    expect { Raven.client.send(:transport).send_event("test", event) }.to raise_error(Faraday::ClientError)

    stubs.verify_stubbed_calls
  end
end
