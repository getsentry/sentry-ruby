# frozen_string_literal: true

RSpec.describe Sentry::Envelope::Item do
  describe '.data_category' do
    [
      ['session', 'session'],
      ['sessions', 'session'],
      ['attachment', 'attachment'],
      ['transaction', 'transaction'],
      ['span', 'span'],
      ['profile', 'profile'],
      ['log', 'log'],
      ['check_in', 'monitor'],
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
