require 'spec_helper'

RSpec.describe Raven::Utils::ExceptionCauseChain do
  describe '.exception_to_array' do
    # Only check causes when they're supported
    if Exception.new.respond_to? :cause
      context 'when the ruby version supports exception causes' do
        context 'when the exception has a cause' do
          let(:exception) { build_exception_with_cause }

          it 'captures the cause' do
            expect(described_class.exception_to_array(exception).length).to eq(2)
          end
        end

        context 'when the exception has nested causes' do
          let(:exception) { build_exception_with_two_causes }

          it 'captures nested causes' do
            expect(described_class.exception_to_array(exception).length).to eq(3)
          end
        end

        context 'when the exception has a recursive cause' do
          let(:exception) { build_exception_with_recursive_cause }

          it 'should handle it gracefully' do
            expect(described_class.exception_to_array(exception).length).to eq(1)
          end
        end
      end
    else
      context 'when the ruby version does not support exception causes' do
        let(:exception) { build_exception_with_two_causes }

        it 'returns the passed in exception' do
          expect(described_class.exception_to_array(exception)).to eq [exception]
        end
      end
    end
  end
end
