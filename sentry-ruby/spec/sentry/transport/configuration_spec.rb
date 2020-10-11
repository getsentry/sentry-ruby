require "spec_helper"

RSpec.describe Sentry::Transport::Configuration do
  describe "#encoding=" do
    it "doesnt accept invalid encodings" do
      expect { subject.encoding = "apple" }.to raise_error(Sentry::Error, 'Unsupported encoding')
    end
    it "sets encoding" do
      subject.encoding = "json"

      expect(subject.encoding).to eq("json")
    end
  end
end
