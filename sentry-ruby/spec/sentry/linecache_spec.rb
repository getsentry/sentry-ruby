require 'spec_helper'
# rubocop:disable Style/WordArray
RSpec.describe Sentry::LineCache do
  describe "#get_file_context" do
    it "returns an array of nils if the path is not valid" do
      expect(subject.get_file_context("/nonexist", 1, 10)).to eq([nil, nil, nil])
    end

    it "returns a variable size depending on context" do
      expect(subject.get_file_context("spec/support/linecache.txt", 3, 2)).to eq(
        [
          ["foo\n", "bar\n"],
          "baz\n",
          ["qux\n", "lorem\n"]
        ]
      )
    end

    it "returns nil if line doesnt exist" do
      expect(subject.get_file_context("spec/support/linecache.txt", 1, 2)).to eq(
        [
          [nil, nil],
          "foo\n",
          ["bar\n", "baz\n"]
        ]
      )
    end

    it "returns a different section of the file based on lineno" do
      expect(subject.get_file_context("./spec/support/linecache.txt", 4, 2)).to eq(
        [
          ["bar\n", "baz\n"],
          "qux\n",
          ["lorem\n", "ipsum\n"]
        ]
      )
    end
  end
end
# rubocop:enable Style/WordArray
