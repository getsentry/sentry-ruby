# frozen_string_literal: true

require_relative "../spec_helper"

SimpleCov.command_name "RSpecIsolated"

RSpec.describe Sentry do
  context "works within a trap context", when: { ruby_engine?: "ruby" } do
    it "doesn't raise error when accessing main hub in trap context" do
      out = `ruby spec/isolated/init.rb`

      expect(out).to include("Sentry::Hub")
    end
  end
end
