require 'spec_helper'

RSpec.describe Raven::Utils::RealIp do
  context "when no ip addresses are provided other than REMOTE_ADDR" do
    subject { Raven::Utils::RealIp.new("REMOTE_ADDR" => "1.1.1.1") }

    it "should return the remote_addr" do
      expect(subject.calculate_ip).to eq("1.1.1.1")
    end
  end

  context "when a list of x-forwarded-for ips is provided" do
    subject do
      Raven::Utils::RealIp.new(
        "HTTP_X_FORWARDED_FOR" => "192.168.0.2, 2.2.2.2, 3.3.3.3, 4.4.4.4",
        "REMOTE_ADDR" => "192.168.0.1"
      )
    end

    it "should return the oldest ancestor that is not a local IP" do
      expect(subject.calculate_ip).to eq("2.2.2.2")
    end
  end

  context "when client/real ips are provided" do
    subject do
      Raven::Utils::RealIp.new(
        "HTTP_X_FORWARDED_FOR" => "2.2.2.2",
        "HTTP_X_REAL_IP" => "4.4.4.4",
        "HTTP_CLIENT_IP" => "3.3.3.3",
        "REMOTE_ADDR" => "192.168.0.1"
      )
    end

    it "should return the oldest ancestor, preferring client/real ips first" do
      expect(subject.calculate_ip).to eq("3.3.3.3")
    end
  end

  context "all provided ip addresses are actually local addresses" do
    subject do
      Raven::Utils::RealIp.new(
        "HTTP_X_FORWARDED_FOR" => "127.0.0.1, ::1, 10.0.0.0",
        "REMOTE_ADDR" => "192.168.0.1"
      )
    end

    it "should return REMOTE_ADDR" do
      expect(subject.calculate_ip).to eq("192.168.0.1")
    end
  end

  context "when an invalid IP is provided" do
    subject do
      Raven::Utils::RealIp.new(
        "HTTP_X_FORWARDED_FOR" => "4.4.4.4.4, 2.2.2.2",
        "REMOTE_ADDR" => "192.168.0.1"
      )
    end

    it "return the eldest valid IP" do
      expect(subject.calculate_ip).to eq("2.2.2.2")
    end
  end

  context "with IPv6 ips" do
    subject do
      Raven::Utils::RealIp.new(
        "HTTP_X_FORWARDED_FOR" => "2001:db8:a0b:12f0::1",
        "REMOTE_ADDR" => "192.168.0.1"
      )
    end

    it "return the eldest valid IP" do
      expect(subject.calculate_ip).to eq("2001:db8:a0b:12f0::1")
    end
  end
end
