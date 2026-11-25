# frozen_string_literal: true

require "open3"

RSpec.describe "Solid Queue recurring task boot in a fresh Rails process" do
  [false, true].each do |eager_load|
    it "passes the boot regression with eager_load #{eager_load}" do
      skip "Solid Queue is not bundled in this matrix cell" unless Gem.loaded_specs.key?("solid_queue")

      fixture = File.expand_path("../fixtures/solid_queue_recurring_boot.rb", __dir__)
      stdout, stderr, status = Open3.capture3({ "EAGER_LOAD" => eager_load.to_s }, RbConfig.ruby, fixture)

      expect(status.exitstatus).to eq(0), stdout + stderr
    end
  end
end
