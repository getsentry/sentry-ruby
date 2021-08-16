require "spec_helper"

RSpec.describe Sentry::DSN do
  subject do
    described_class.new(
      "http://12345:67890@sentry.localdomain:3000/sentry/42"
    )
  end

  it "initializes with correct attributes set" do
    expect(subject.project_id).to eq("42")
    expect(subject.public_key).to eq("12345")
    expect(subject.secret_key).to eq("67890")

    expect(subject.scheme).to     eq("http")
    expect(subject.host).to       eq("sentry.localdomain")
    expect(subject.port).to       eq(3000)
    expect(subject.path).to       eq("/sentry")

    expect(subject.to_s).to     eq("http://12345:67890@sentry.localdomain:3000/sentry/42")
  end

  describe "#envelope_endpoint" do
    it "assembles correct envelope endpoint" do
      expect(subject.envelope_endpoint).to eq("/sentry/api/42/envelope/")
    end
  end

  describe "#server" do
    it "returns scheme + host" do
      expect(subject.server).to eq("http://sentry.localdomain:3000")
    end
  end

  describe "#csp_report_uri" do
    it "returns the correct uri" do
      expect(subject.csp_report_uri).to eq("http://sentry.localdomain:3000/api/42/security/?sentry_key=12345")
    end
  end
end
