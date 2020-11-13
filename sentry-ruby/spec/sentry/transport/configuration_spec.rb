require "spec_helper"

RSpec.describe Sentry::Transport::Configuration do
  describe "#transport_class=" do
    it "doesn't accept non-class argument" do
      expect { subject.transport_class = "foo" }.to raise_error(Sentry::Error, "config.transport.transport_class must a class. got: String")
    end

    it "accepts class argument" do
      subject.transport_class = Sentry::DummyTransport

      expect(subject.transport_class).to eq(Sentry::DummyTransport)
    end
  end
end
