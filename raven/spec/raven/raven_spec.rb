require File::expand_path('../../spec_helper', __FILE__)
require 'raven'

describe 'A raven client' do

  context 'being initialized with a DSN string' do
    before do
      @client = Raven::Client.new('http://12345:67890@sentry.localdomain/sentry/42')
    end

    it 'should have a server' do
      @client.server.should == 'http://sentry.localdomain/sentry'
    end

    it 'should have a public key' do
      @client.public_key.should == '12345'
    end

    it 'should have a secret key' do
      @client.secret_key.should == '67890'
    end

    it 'should have a project ID' do
      @client.project_id.should == '42'
    end
  end

  context 'being initialized with a DSN option' do
    before do
      @client = Raven::Client.new(:dsn => 'http://12345:67890@sentry.localdomain/sentry/42')
    end

    it 'should have a server' do
      @client.server.should == 'http://sentry.localdomain/sentry'
    end

    it 'should have a public key' do
      @client.public_key.should == '12345'
    end

    it 'should have a secret key' do
      @client.secret_key.should == '67890'
    end

    it 'should have a project ID' do
      @client.project_id.should == '42'
    end
  end

end