# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::Test::Application do
  include Sentry::Rails::TestHelper

  def load_hook_state
    %i[@load_hooks @loaded @run_once].select { |name| ActiveSupport.instance_variable_defined?(name) }.map do |name|
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

    it "releases the app's filter parameters from ActiveRecord" do
      app = make_basic_app
      expect(ActiveRecord::Base.filter_attributes).not_to be_empty

      app.cleanup!

      expect(ActiveRecord::Base.filter_attributes).to be_empty
    end

    it "releases the encrypted attribute listeners the app registered" do
      skip "ActiveRecord::Encryption is not available" unless defined?(ActiveRecord::Encryption)

      app = make_basic_app
      expect(ActiveRecord::Encryption.encrypted_attribute_declaration_listeners).not_to be_empty

      app.cleanup!

      expect(ActiveRecord::Encryption.encrypted_attribute_declaration_listeners).to be_blank
    end

    it "releases the sensitive attribute listeners the app registered" do
      skip "ActiveRecord::FilterAttributeHandler is not available" unless defined?(ActiveRecord::FilterAttributeHandler)

      app = make_basic_app
      listeners = -> { ActiveRecord::FilterAttributeHandler.instance_variable_get(:@sensitive_attribute_declaration_listeners) }
      expect(listeners.call).not_to be_empty

      app.cleanup!

      expect(listeners.call).to be_blank
    end

    it "releases the Action Cable server built for the app" do
      app = make_basic_app
      server = ActionCable.server

      app.cleanup!

      expect(ActionCable.server).not_to equal(server)
    end

    it "releases the main_app route helper bound to the app" do
      app = make_basic_app
      expect(ActionDispatch::Routing::RouteSet::MountedHelpers.method_defined?(:main_app)).to be(true)

      app.cleanup!

      expect(ActionDispatch::Routing::RouteSet::MountedHelpers.method_defined?(:main_app)).to be(false)
    end

    it "releases the cache store built for the app" do
      app = make_basic_app
      expect(Rails.cache).not_to be_nil

      app.cleanup!

      expect(Rails.cache).to be_nil
    end

    it "releases the partial rendering cache built for the app" do
      app = make_basic_app
      cache = ActionView::PartialRenderer.collection_cache

      app.cleanup!

      expect(ActionView::PartialRenderer.collection_cache).not_to equal(cache)
    end
  end
end
