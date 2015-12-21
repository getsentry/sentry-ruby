require 'spec_helper'

describe Raven::OkJson do
  data = [
    OpenStruct.new(:key => 'foo', :val => 'bar', :enc_key => '"foo"', :enc_val => '"bar"'),
    OpenStruct.new(:key => :foo, :val => :bar, :enc_key => '"foo"', :enc_val => '"bar"'),
    OpenStruct.new(:key => 1, :val => 1, :enc_key => '"1"', :enc_val => '1')
  ]

  data.each do |obj|
    it "works with #{obj.key.class} keys" do
      expect(Raven::OkJson.encode(obj.key => 'bar')).to eq "{#{obj.enc_key}:\"bar\"}"
    end

    it "works with #{obj.val.class} values" do
      expect(Raven::OkJson.encode('bar' => obj.val)).to eq "{\"bar\":#{obj.enc_val}}"
    end

    it "works with an array of #{obj.val.class}s" do
      expect(Raven::OkJson.encode('bar' => [obj.val])).to eq "{\"bar\":[#{obj.enc_val}]}"
    end

    it "works with a hash of #{obj.val.class}s" do
      expect(Raven::OkJson.encode('bar' => {obj.key => obj.val})).to eq "{\"bar\":{#{obj.enc_key}:#{obj.enc_val}}}"
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
