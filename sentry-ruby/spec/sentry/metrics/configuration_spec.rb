# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::Configuration do
  let(:stringio) { StringIO.new }
  subject { described_class.new(::Logger.new(stringio)) }

  %i[enabled enable_code_locations before_emit].each do |method|
    describe "#{method}=" do
      it 'logs deprecation warning' do
        subject.send("#{method}=", true)

        expect(stringio.string).to include(
          "WARN -- sentry: `config.metrics` is now deprecated and will be removed in the next major."
        )
      end
    end
  end
end
