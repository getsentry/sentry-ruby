require 'spec_helper'

RSpec.describe Sentry::Utils::RealIp do
  context "when no ip addresses are provided other than REMOTE_ADDR" do
    subject { Sentry::Utils::RealIp.new(:remote_addr => "1.1.1.1") }

    it "should return the remote_addr" do
      expect(subject.calculate_ip).to eq("1.1.1.1")
    end
  end

  context "when a list of x-forwarded-for ips is provided" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "2.2.2.2, 3.3.3.3, 4.4.4.4, 192.168.0.2",
        :remote_addr => "192.168.0.1"
      )
    end

    it "should return the oldest ancestor that is not a local IP" do
      expect(subject.calculate_ip).to eq("4.4.4.4")
    end
  end

  context "when client/real ips are provided" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "2.2.2.2",
        :real_ip => "4.4.4.4",
        :client_ip => "3.3.3.3",
        :remote_addr => "192.168.0.1"
      )
    end

    it "should return the oldest ancestor, preferring client/real ips first" do
      expect(subject.calculate_ip).to eq("3.3.3.3")
    end
  end

  context "all provided ip addresses are actually local addresses" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "127.0.0.1, ::1, 10.0.0.0",
        :remote_addr => "192.168.0.1"
      )
    end

    it "should return REMOTE_ADDR" do
      expect(subject.calculate_ip).to eq("192.168.0.1")
    end
  end

  context "when custom proxies are provided" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "2.2.2.2, 3.3.3.3, 4.4.4.4",
        :trusted_proxies => ["4.4.4.4"]
      )
    end

    it "should return the first IP not in the trusted proxy list" do
      expect(subject.calculate_ip).to eq("3.3.3.3")
    end
  end

  context "when custom proxies are provided as IPAddr" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "2.2.2.2, 3.3.3.3, 4.4.4.4",
        :trusted_proxies => [IPAddr.new("4.4.4.4")]
      )
    end

    it "should return the first IP not in the trusted proxy list" do
      expect(subject.calculate_ip).to eq("3.3.3.3")
    end
  end

  context "when an invalid IP is provided" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "4.4.4.4.4, 2.2.2.2",
        :remote_addr => "192.168.0.1"
      )
    end

    it "return the eldest valid IP" do
      expect(subject.calculate_ip).to eq("2.2.2.2")
    end
  end

  context "with IPv6 ips" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "2001:db8:a0b:12f0::1",
        :remote_addr => "192.168.0.1"
      )
    end

    it "return the eldest valid IP" do
      expect(subject.calculate_ip).to eq("2001:db8:a0b:12f0::1")
    end
  end
  
  context "when custom proxies are provided as IPAddr as IP subnet" do
    subject do
      Sentry::Utils::RealIp.new(
        :forwarded_for => "2.2.2.2, 3.3.3.3, 4.4.4.4",
        :trusted_proxies => [IPAddr.new("4.4.4.0/24")]
      )
    end

    it "should return the first IP not in the trusted proxy list" do
      expect(subject.calculate_ip).to eq("3.3.3.3")
    end
  end
end
