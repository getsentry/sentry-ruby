require "spec_helper"

RSpec.describe Sentry::Scope do
  describe "#initialize" do
    it "contains correct defaults" do
      expect(subject.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(subject.extra.dig(:server, :os).keys).to match_array([:name, :version, :build, :kernel_version])
      expect(subject.extra.dig(:server, :runtime, :version)).to match(/ruby/)
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.transactions).to eq([])
    end
  end
end
