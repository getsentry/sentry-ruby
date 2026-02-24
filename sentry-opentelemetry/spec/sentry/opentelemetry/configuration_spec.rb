# frozen_string_literal: true

RSpec.describe Sentry::OTLP::Configuration do
  subject { described_class.new }

  describe "#initialize" do
    it "sets default values" do
      expect(subject.enabled).to eq(false)
      expect(subject.setup_otlp_traces_exporter).to eq(true)
      expect(subject.setup_propagator).to eq(true)
    end
  end

  describe "accessors" do
    it "allows setting enabled" do
      subject.enabled = true
      expect(subject.enabled).to eq(true)
    end

    it "allows setting setup_otlp_traces_exporter" do
      subject.setup_otlp_traces_exporter = false
      expect(subject.setup_otlp_traces_exporter).to eq(false)
    end

    it "allows setting setup_propagator" do
      subject.setup_propagator = false
      expect(subject.setup_propagator).to eq(false)
    end
  end
end
