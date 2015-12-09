require 'spec_helper'

describe Raven::OkJson do
  ['foo', :foo].each do |obj|
    it "works with #{obj.class} keys" do
      expect(Raven::OkJson.encode(obj => 'bar')).to eq '{"foo":"bar"}'
    end

    it "works with #{obj.class} values" do
      expect(Raven::OkJson.encode('bar' => obj)).to eq '{"bar":"foo"}'
    end

    it "works with an array of #{obj.class}s" do
      expect(Raven::OkJson.encode('bar' => [obj])).to eq '{"bar":["foo"]}'
    end

    it "works with a hash of #{obj.class}s" do
      expect(Raven::OkJson.encode('bar' => {obj => obj})).to eq '{"bar":{"foo":"foo"}}'
    end
  end

  it 'encodes anything that responds to to_s' do
    data = [
      (1..5),
      :symbol,
      1/0.0,
      0/0.0
    ]
    expect(Raven::OkJson.encode(data)).to eq "[\"1..5\",\"symbol\",\"Infinity\",\"NaN\"]"
  end

  it 'does not parse scientific notation' do
    expect(Raven::OkJson.decode("[123e090]")).to eq ["123e090"]
  end

  it 'it raises the correct error on strings that look like incomplete objects' do
    expect{Raven::OkJson.decode("{")}.to raise_error(Raven::OkJson::Error)
    expect{Raven::OkJson.decode("[")}.to raise_error(Raven::OkJson::Error)
  end
end
