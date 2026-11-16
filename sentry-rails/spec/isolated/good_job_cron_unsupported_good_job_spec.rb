# frozen_string_literal: true

require "open3"

RSpec.describe "GoodJob cron with an unsupported GoodJob in a fresh Rails process" do
  it "warns instead of monitoring without sharing GoodJob state" do
    skip "GoodJob is not bundled in this matrix cell" unless Gem.loaded_specs.key?("good_job")

    fixture = File.expand_path("../fixtures/good_job_cron_unsupported.rb", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-S", "rspec", fixture)

    expect(status.exitstatus).to eq(0), stdout + stderr
  end
end
