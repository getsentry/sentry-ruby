# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::Test::Application do
  include Sentry::Rails::TestHelper

  def load_hook_state
    %i[@load_hooks @loaded].map do |name|
      ActiveSupport.instance_variable_get(name).transform_values(&:dup)
    end
  end

  describe "#cleanup!" do
    it "restores the ActiveSupport load hook state to what it was before the boot" do
      before_boot = load_hook_state

      app = make_basic_app
      expect(load_hook_state).not_to eq(before_boot)

      app.cleanup!

      expect(load_hook_state).to eq(before_boot)
    end
  end
end
