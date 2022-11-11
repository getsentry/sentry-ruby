require 'spec_helper'

RSpec.describe Sentry::OpenTelemetry::SpanProcessor do
  let(:subject) { described_class.instance }

  before { subject.clear }

  describe "singleton instance" do
    it "has empty span_map" do
      expect(subject.span_map).to eq({})
    end
  end
end
