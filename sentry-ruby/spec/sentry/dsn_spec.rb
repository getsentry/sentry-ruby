require "spec_helper"

RSpec.describe Sentry::DSN do
  it "initializes with correct attributes set" do
    subject = described_class.new(
      "http://12345:67890@sentry.localdomain:3000/sentry/42"
    )

    expect(subject.project_id).to eq("42")
    expect(subject.public_key).to eq("12345")
    expect(subject.secret_key).to eq("67890")

    expect(subject.scheme).to     eq("http")
    expect(subject.host).to       eq("sentry.localdomain")
    expect(subject.port).to       eq(3000)
    expect(subject.path).to       eq("/sentry")

    expect(subject.to_s).to     eq("http://12345:67890@sentry.localdomain:3000/sentry/42")
  end
end
