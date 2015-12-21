describe Raven::Transports::HTTP do
  it 'should set a custom User-Agent' do
    Raven.configure do |config|
      config.server = 'http://12345:67890@sentry.localdomain/sentry/42'
    end

    expect(Raven.client.send(:transport).conn.headers[:user_agent]).to eq("sentry-ruby/#{Raven::VERSION}")
  end
end
