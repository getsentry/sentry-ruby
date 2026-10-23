# frozen_string_literal: true

RSpec.describe Sentry::Utils::Latency do
  let(:started_at) { Time.utc(2026, 1, 1, 12, 0, 0) }

  around do |example|
    Timecop.freeze(started_at + 2.5) { example.run }
  end

  it "measures the milliseconds since a Time" do
    expect(described_class.milliseconds_since(started_at)).to eq(2_500.0)
  end

  it "measures the milliseconds since an ISO 8601 String" do
    expect(described_class.milliseconds_since(started_at.iso8601(3))).to eq(2_500.0)
  end

  it "measures nothing without a time" do
    expect(described_class.milliseconds_since(nil)).to be_nil
  end
end
