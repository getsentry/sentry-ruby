require "test_helper"

# Raven sometimes has to deal with some weird JSON. This makes sure whatever
# JSON implementation we use handles it in the way that we expect.
class JSONTest < Minitest::Spec
  # Strings

  it "works with string keys and values" do
    assert_equal "{\"foo\":\"bar\"}", JSON.dump("foo" => "bar")
  end

  it "works with an array of strings" do
    assert_equal "{\"foo\":[\"bar\"]}", JSON.dump("foo" => ["bar"])
  end

  it "works with a nested hash of strings" do
    assert_equal "{\"foo\":{\"foo\":\"bar\"}}", JSON.dump("foo" => { "foo" => "bar" })
  end

  # Symbols

  it "works with symbol keys and values" do
    assert_equal "{\"foo\":\"bar\"}", JSON.dump(:foo => :bar)
  end

  it "works with an array of symbols" do
    assert_equal "{\"foo\":[\"bar\"]}", JSON.dump(:foo => [:bar])
  end

  it "works with a nested hash of strings" do
    assert_equal "{\"foo\":{\"foo\":\"bar\"}}", JSON.dump(:foo => { :foo => :bar })
  end

  # Integers

  it "works with integer keys and values" do
    assert_equal "{\"1\":2}", JSON.dump(1 => 2)
  end

  it "works with an array of symbols" do
    assert_equal "{\"1\":[2]}", JSON.dump(1 => [2])
  end

  it "works with a nested hash of strings" do
    assert_equal "{\"1\":{\"1\":2}}", JSON.dump( 1 => { 1 => 2 })
  end

  # Other

  it "encodes anything that responds to to_s" do
    data = [
      :symbol,
      1 / 0.0,
      0 / 0.0
    ]
    assert_equal "[\"symbol\",Infinity,NaN]", JSON.dump(data)
  end

  if RUBY_VERSION.to_f >= 2.0 # 1.9 just hangs on this.
    it "raises the correct error on strings that look like incomplete objects" do
      assert_raises JSON::ParserError do JSON.parse("{") end
      assert_raises JSON::ParserError do JSON.parse("[") end
    end

    it "accepts any encoding which is internally valid" do
      test_json = %({"example": "test"})
      test_hash = { "example" => "test" }
      assert_equal test_hash, JSON.parse(test_json)
      assert_equal test_hash, JSON.parse(test_json.encode("utf-16"))
      assert_equal test_hash, JSON.parse(test_json.encode("US-ASCII"))
    end

    it "blows up on circular references" do
      data = {}
      data["data"] = data
      data["ary"] = []
      data["ary"].push("x" => data["ary"])
      data["ary2"] = data["ary"]
      data["leave intact"] = { "not a circular reference" => true }

      if RUBY_PLATFORM == "java"
        assert_raises JSON.dump(data)
      else
        assert_raises SystemStackError do JSON.dump(data) end
      end
    end
  end
end
