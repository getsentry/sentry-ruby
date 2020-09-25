require "spec_helper"

RSpec.describe Sentry::Scope do
  describe "#initialize" do
    it "contains correct defaults" do
      expect(subject.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(subject.extra.dig(:server, :os).keys).to match_array([:name, :version, :build, :kernel_version])
      expect(subject.extra.dig(:server, :runtime, :version)).to match(/ruby/)
      expect(subject.tags).to eq({})
      expect(subject.user).to eq({})
      expect(subject.fingerprint).to eq([])
      expect(subject.transactions).to eq([])
    end
  end

  describe "#apply_to_event" do
    subject do
      scope = described_class.new
      scope.tags = {foo: "bar"}
      scope.user = {id: 1}
      scope.transactions = ["WelcomeController#index"]
      scope.fingerprint = ["foo"]
      scope
    end
    let(:client) do
      Sentry::Client.new(Sentry::Configuration.new.tap { |c| c.scheme = "dummy" } )
    end
    let(:event) do
      client.event_from_message("test message")
    end

    it "applies the contextual data to event" do
      subject.apply_to_event(event)
      expect(event.tags).to eq({foo: "bar"})
      expect(event.user).to eq({id: 1})
      expect(event.transaction).to eq("WelcomeController#index")
      expect(event.breadcrumbs).to be_a(Sentry::BreadcrumbBuffer)
      expect(event.fingerprint).to eq(["foo"])
      expect(event.extra.dig(:server, :os).keys).to match_array([:name, :version, :build, :kernel_version])
      expect(event.extra.dig(:server, :runtime, :version)).to match(/ruby/)
    end

    it "doesn't override event's pre-existing data" do
      event.tags = {foo: "baz"}
      event.user = {id: 2}
      event.extra = {additional_info: "nothing"}

      subject.apply_to_event(event)
      expect(event.tags).to eq({foo: "baz"})
      expect(event.user).to eq({id: 2})
      expect(event.extra[:additional_info]).to eq("nothing")
      expect(event.extra.dig(:server, :runtime, :version)).to match(/ruby/)
    end
  end
end
