# Encoding: utf-8

require 'spec_helper'

describe Raven::Processor::RequestMethodData do
  TESTED_METHODS = [
    "GET",
    "PATCH",
    "POST",
    "PUT",
  ].freeze
  TESTED_CONFIGURATIONS = [
    ["POST", "PUT", "PATCH"],
    ["POST"],
    ["PUT"],
    ["PATCH"],
    ["POST", "PUT"],
    ["PUT", "PATCH"],
    ["POST", "PATCH"],
    [],
  ].freeze

  let(:configuration) do
    double("configuration", sanitize_data_for_request_methods: configured_methods)
  end
  let(:result) { processor.process(data) }
  let(:client) { double("client", configuration: configuration) }
  let(:processor) { described_class.new(client) }
  let(:data) do
    {
      :request => {
        :method => method,
        :data => {
          "sensitive_stuff" => "TOP_SECRET-GAMMA"
        }
      }
    }
  end

  TESTED_CONFIGURATIONS.each do |sanitized_methods|
    context "configured_methods: #{sanitized_methods}" do
      let(:configured_methods) { sanitized_methods }

      context "sanitized methods: #{sanitized_methods}" do
        sanitized_methods.each do |sanitized_method|
          let(:method) { sanitized_method }

          it "sanitized the data for #{sanitized_method}" do
            expect(result[:request][:data]).to eq("********")
          end
        end
      end

      unsanitized_methods = TESTED_METHODS - sanitized_methods
      context "unsanitized methods: #{unsanitized_methods}" do
        unsanitized_methods.each do |unsanitized_method|
          let(:method) { unsanitized_method }

          it "did not sanitize the data for #{unsanitized_method}" do
            expect(result[:request][:data]).to eq({"sensitive_stuff" => "TOP_SECRET-GAMMA"})
          end
        end
      end
    end
  end
end
