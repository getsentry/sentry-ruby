# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Utils::RingBuffer do
  subject(:buffer) { described_class.new(2) }

  it "keeps the most recent unique values" do
    buffer.set("a", 1)
    buffer.set("b", 2)
    buffer.set("a", 3)
    buffer.set("c", 4)

    expect(buffer.values).to eq("a" => 3, "c" => 4)
  end

  it "copies and clears independently" do
    buffer.set("a", 1)
    copy = buffer.dup

    copy.set("b", 2)
    copy.clear

    expect(buffer.values).to eq("a" => 1)
    expect(copy).to be_empty
  end
end
