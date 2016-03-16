require 'spec_helper'

describe Raven::Client do
  let(:config) { Raven::Configuration.new }
  let(:instance) { Raven::Client.new(config) }

  context '.process_event' do
    let(:dummy_processor) { instance_double("Raven::Processor") }
    let(:exc_hash) do
      {
        :foo => 'bar',
        :modules => {
          'rails' => '1.0.0',
          'raven-ruby' => '1.0.5'
        },
        :exception => {
          :values => [
            { :name => 'first', :stacktrace => %w(a b c) },
            { :name => 'second', :stacktrace => %w(d e f) },
            { :name => 'third', :stacktrace => %w(x y z) }
          ]
        }
      }
    end

    before { config.processors = [double(:new => dummy_processor)] }

    context 'by default' do
      it 'sanitizes all data' do
        expect(dummy_processor).to receive(:process).with(exc_hash).and_return('processed')
        expect(instance.send(:process_event, exc_hash)).to eq('processed')
      end
    end

    context 'with internal data sanitization disabled' do
      let(:filtered_hash) do
        {
          :foo => 'bar',
          :exception => {
            :values => [
              { :name => 'first' },
              { :name => 'second' },
              { :name => 'third' }
            ]
          }
        }
      end

      before { config.sanitize_internal_data = false }

      it 'does not sanitize modules and exceptions' do
        # Confirm we're sanitizing it properly
        expect(dummy_processor).to receive(:process) do |hash|
          expect(hash[:modules]).to eq(nil)

          hash[:exception][:values].each do |row|
            expect(row[:_trace_id]).to_not eq(nil)
            expect(row[:stacktrace]).to eq(nil)
          end

          hash.merge(:_filtered => 1)
        end

        result = instance.send(:process_event, exc_hash.dup)
        # Make sure we sent it through the procsesor and care about the response
        expect(result.delete(:_filtered)).to eq(1)
        # Confirm we properly restored the modules/stacktrace
        expect(result).to eq(exc_hash)
      end
    end
  end
end
