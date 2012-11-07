require 'spec_helper'
require 'raven'
require 'raven/rails/controller_methods'

describe Raven::Rails::ControllerMethods do
  include described_class

  let(:env) { {"foo" => "bar"} }
  let(:request) { double('request', :env => env) }
  let(:options) { double('options') }

  describe "#capture_message" do
    let(:message) { double('message') }

    it "captures a message with the request environment" do
      Raven::Rack.should_receive(:capture_message).with(message, env, options)
      capture_message(message, options)
    end
  end

  describe "#capture_exception" do
    let(:exception) { double('exception') }

    it "captures a exception with the request environment" do
      Raven::Rack.should_receive(:capture_exception).with(exception, env, options)
      capture_exception(exception, options)
    end
  end
end
