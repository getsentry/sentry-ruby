require 'spec_helper'

describe Raven::BetterAttrAccessor do

  let :klass do
    Class.new do
      include Raven::BetterAttrAccessor

      attr_accessor :a
      attr_accessor :b, :default => []
      attr_accessor :c
    end
  end

  let :child do
    Class.new klass do
      attr_accessor :d
    end
  end

  subject{ klass.new }

  describe 'the reader method' do
    context 'when a value is not set' do
      it 'should default to nil' do
        expect(subject.a).to eq nil
      end
      it 'should use a default value if provided' do
        expect(subject.b).to eq []
        expect(subject.instance_variable_get '@b').to eq []
      end
    end

    context 'when a value is set' do
      before do
        subject.a = 'foo'
        subject.b = :bar
        subject.c = false
      end

      it 'should save the value' do
        expect(subject.a).to eq 'foo'
      end
      it 'should save a boolean `false` value' do
        expect(subject.c).to eq false
      end
      it 'should no longer return the default' do
        expect(subject.b).to eq :bar
      end
    end

    context 'when a default value is directly modified' do
      before { subject.b << 9 }
      it 'should not affect a new instance' do
        expect(klass.new.b).to eq []
      end
    end
  end

  describe '.attributes' do
    it 'should be a Set of all attributes set up' do
      expect(klass.attributes).to be_a Set
      expect(klass.attributes).to eq %w[a b c].to_set
    end
    it 'should work with inheritance' do
      expect(child.attributes).to eq %w[d a b c].to_set
    end
  end

  describe '#attributes' do
    it 'should return a hash of all attributes' do
      subject.a = {'foo' => :bar}
      subject.b << 8
      expect(subject.attributes).to eq \
        'a' => {'foo' => :bar},
        'b' => [8],
        'c' => nil
    end

    describe 'inheritance' do
      subject{ child.new }

      before do
        subject.a = 21
        subject.d = true
      end

      it 'should work' do
        expect(subject.attributes).to eq \
          'a' => 21,
          'b' => [],
          'c' => nil,
          'd' => true
      end
    end
  end

end
