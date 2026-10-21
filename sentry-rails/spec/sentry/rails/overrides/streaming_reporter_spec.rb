# frozen_string_literal: true

require 'spec_helper'
require 'sentry/rails/overrides/streaming_reporter'

RSpec.describe Sentry::Rails::Overrides::StreamingReporter do
  it "keeps ActionController::Live's private method private when prepended" do
    live_module = Module.new do
      private

      def log_error(_exception)
      end
    end
    live_module.prepend(described_class)
    controller_class = Class.new { include live_module }

    expect(controller_class.public_method_defined?(:log_error)).to be(false)
    expect(controller_class.private_method_defined?(:log_error)).to be(true)
  end
end
