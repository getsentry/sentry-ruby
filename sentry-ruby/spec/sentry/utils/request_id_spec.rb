require "spec_helper"

RSpec.describe Sentry::Utils::RequestId do
  describe ".read_from" do
    subject { Sentry::Utils::RequestId.read_from(env_hash) }

    context "when HTTP_X_REQUEST_ID is available" do
      let(:env_hash) { { "HTTP_X_REQUEST_ID" => "request-id-sorta" } }

      it { is_expected.to eq("request-id-sorta") }
    end

    context "when action_dispatch.request_id is available (from Rails middleware)" do
      let(:env_hash) { { "action_dispatch.request_id" => "request-id-kinda" } }

      it { is_expected.to eq("request-id-kinda") }
    end

    context "when no request-id is available" do
      let(:env_hash) { { "foo" => "bar" } }

      it { is_expected.to be_nil }
    end
  end
end
