# frozen_string_literal: true

RSpec.describe Sentry::Transport::RateLimits do
  subject { described_class.new }

  let(:now) { Time.now }

  describe "#update" do
    [nil, "error"].each do |category|
      context "with category #{category.inspect}" do
        it "does not replace a longer deadline with a shorter one" do
          subject.update(category, now + 3600)
          subject.update(category, now + 10)

          expect(subject.to_h).to eq({ category => now + 3600 })
        end

        it "replaces a shorter deadline with a longer one" do
          subject.update(category, now + 10)
          subject.update(category, now + 3600)

          expect(subject.to_h).to eq({ category => now + 3600 })
        end
      end
    end
  end

  describe "#to_h" do
    it "returns a copy that does not change the rate limits" do
      subject.update("error", now + 3600)

      subject.to_h["error"] = now - 10

      expect(subject.to_h).to eq({ "error" => now + 3600 })
    end
  end
end
