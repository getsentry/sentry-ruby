# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Envelope::Item do
  describe '.data_category' do
    [
      ['session', 'session'],
      ['sessions', 'session'],
      ['attachment', 'attachment'],
      ['transaction', 'transaction'],
      ['span', 'span'],
      ['profile', 'profile'],
      ['check_in', 'monitor'],
      ['statsd', 'metric_bucket'],
      ['metric_meta', 'metric_bucket'],
      ['event', 'error'],
      ['client_report', 'internal'],
      ['unknown', 'default']
    ].each do |item_type, data_category|
      it "maps item type #{item_type} to data category #{data_category}" do
        expect(described_class.data_category(item_type)).to eq(data_category)
      end
    end
  end
end
