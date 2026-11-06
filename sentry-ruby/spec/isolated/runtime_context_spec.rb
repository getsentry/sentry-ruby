# frozen_string_literal: true

# isolated tests need a SimpleCov name otherwise they will overwrite coverage
SimpleCov.command_name "RSpecIsolatedRuntimeContext"

RSpec.describe Sentry do
  it "reports YJIT in the runtime context when it's enabled after init" do
    skip "YJIT can't be enabled at runtime" unless defined?(RubyVM::YJIT.enable)

    versions = `ruby spec/isolated/runtime_context.rb`.lines(chomp: true)

    expect(versions.size).to eq(2)
    expect(versions).to all(include("+YJIT"))
  end
end
