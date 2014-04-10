require File.expand_path('../../spec_helper', __FILE__)
require 'raven'

describe Raven::OkJson do

  ['foo', :foo].each do |obj|
    it "works with #{obj.class} keys" do
      Raven::OkJson.encode(obj => 'bar').should eq '{"foo":"bar"}'
    end

    it "works with #{obj.class} values" do
      Raven::OkJson.encode('bar' => obj).should eq '{"bar":"foo"}'
    end

    it "works with an array of #{obj.class}s" do
      Raven::OkJson.encode('bar' => [obj]).should eq '{"bar":["foo"]}'
    end

    it "works with a hash of #{obj.class}s" do
      Raven::OkJson.encode('bar' => {obj => obj}).should eq '{"bar":{"foo":"foo"}}'
    end
  end

end
