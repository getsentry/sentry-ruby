# frozen_string_literal: true

require_relative "../spec_helper"

# isolated tests need a SimpleCov name otherwise they will overwrite coverage
SimpleCov.command_name "RSpecIsolatedInit"

RSpec.describe Sentry do
  context "works within a trap context", when: { ruby_engine?: "ruby" } do
    it "doesn't raise error when accessing main hub in trap context" do
      out = `ruby spec/isolated/init.rb`

      expect(out).to include("Sentry::Hub")
    end
  end
end
