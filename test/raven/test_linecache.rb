require 'test_helper'

class RavenLinecacheTest < Raven::Test
  def setup
    @linecache = Raven::LineCache.new
  end

  it "returns an array of nils if the path is not valid" do
    assert_equal [nil, nil, nil], @linecache.get_file_context("/nonexist", 1, 10)
  end

  it "returns a variable size depending on context" do
    expected = [
      ["foo\n", "bar\n"],
      "baz\n",
      ["qux\n", "lorem\n"]
    ]
    assert_equal expected, @linecache.get_file_context("spec/support/linecache.txt", 3, 2)
  end

  it "returns nil if line doesnt exist" do
    expected = [
      [nil, nil],
      "foo\n",
      ["bar\n", "baz\n"]
    ]
    assert_equal expected, @linecache.get_file_context("spec/support/linecache.txt", 1, 2)
  end

  it "returns a different section of the file based on lineno" do
    expected = [
      ["bar\n", "baz\n"],
      "qux\n",
      ["lorem\n", "ipsum\n"]
    ]

    assert_equal expected, @linecache.get_file_context("./spec/support/linecache.txt", 4, 2)
  end
end
