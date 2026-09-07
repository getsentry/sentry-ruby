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
      ['log', 'log_item'],
      ['trace_metric', 'trace_metric'],
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

  describe '.byte_data_category' do
    [
      ['log_item', 'log_byte'],
      ['trace_metric', 'trace_metric_byte'],
      ['error', nil],
      ['transaction', nil],
      ['default', nil]
    ].each do |data_category, byte_category|
      it "maps data category #{data_category} to byte category #{byte_category.inspect}" do
        expect(described_class.byte_data_category(data_category)).to eq(byte_category)
      end
    end
  end

  describe '#item_count' do
    it "returns the item_count header when present" do
      item = described_class.new({ type: "log", item_count: 5 }, { items: [] })
      expect(item.item_count).to eq(5)
    end

    it "defaults to 1 when the header is absent" do
      item = described_class.new({ type: "event" }, {})
      expect(item.item_count).to eq(1)
    end
  end

  describe '#lost_event_byte_size' do
    it "returns the serialized payload byte size for byte-tracked items" do
      payload = { items: [{ body: "hello" }] }
      item = described_class.new({ type: "log", item_count: 1 }, payload)
      expect(item.lost_event_byte_size).to eq(JSON.generate(payload).bytesize)
      expect(item.lost_event_byte_size).to be > 0
    end

    it "uses the payload as-is when it is already serialized" do
      payload = JSON.generate({ items: [{ body: "hello" }] })
      item = described_class.new({ type: "log", item_count: 1 }, payload)
      expect(item.lost_event_byte_size).to eq(payload.bytesize)
    end

    it "returns nil for items without a byte category" do
      item = described_class.new({ type: "event" }, { foo: "bar" })
      expect(item.lost_event_byte_size).to be_nil
    end
  end

  describe "json 3.0 encoding error handling" do
    # json 3.0+ raises Encoding::UndefinedConversionError (a subclass of
    # EncodingError) instead of just warning when JSON.generate encounters
    # a String tagged with a non-UTF-8 encoding that contains bytes invalid
    # for the target encoding. Simulate that here regardless of the json
    # gem version actually loaded.
    let(:invalid_string) { "\xFF\xFEinvalid".dup.force_encoding(Encoding::BINARY) }

    before do
      call_count = 0

      allow(JSON).to receive(:generate).and_wrap_original do |original, *args|
        call_count += 1
        raise EncodingError, "simulated json 3.0 encoding error" if call_count == 1

        original.call(*args)
      end
    end

    it "recovers in #to_s by sanitizing the payload and retrying" do
      item = described_class.new({ type: "event" }, { message: invalid_string })
      expect { item.to_s }.not_to raise_error
    end

    it "recovers in #lost_event_byte_size" do
      item = described_class.new({ type: "log", item_count: 1 }, { items: [{ body: invalid_string }] })
      expect { item.lost_event_byte_size }.not_to raise_error
    end

    it "recovers in #size_breakdown" do
      item = described_class.new({ type: "event" }, { message: invalid_string })
      expect { item.size_breakdown }.not_to raise_error
    end
  end
end
