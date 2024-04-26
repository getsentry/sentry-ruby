require "spec_helper"

return unless defined?(StackProf)

RSpec.describe Sentry::Profiler do
  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
      config.profiles_sample_rate = 1.0
    end
  end

  before { StackProf.stop }

  let(:subject) { described_class.new(Sentry.configuration) }

  # profiled with following code
  # module Bar
  #   module Foo
  #     def self.foo
  #       1e6.to_i.times { 2**2 }
  #     end
  #   end

  #   def self.bar
  #     Foo.foo
  #     sleep 0.1
  #   end
  # end
  #
  # Bar.bar
  let(:stackprof_results) do
    data = StackProf::Report.from_file('spec/support/stackprof_results.json').data
    # relative dir differs on each machine
    data[:frames].each { |_id, fra| fra[:file].gsub!(/<dir>/, Dir.pwd) }
    data
  end

  describe '#start' do
    context 'without sampling decision' do
      it 'does not start StackProf' do
        expect(StackProf).not_to receive(:start)
        subject.start
        expect(subject.started).to eq(false)
      end
    end

    context 'with sampling decision' do
      it 'does not start StackProf if not sampled' do
        subject.set_initial_sample_decision(false)
        expect(StackProf).not_to receive(:start)
        subject.start
        expect(subject.started).to eq(false)
      end

      it 'starts StackProf if sampled' do
        subject.set_initial_sample_decision(true)

        expect(StackProf).to receive(:start).with(
          interval: 1e6 / 101,
          mode: :wall,
          raw: true,
          aggregate: false
        ).and_call_original

        subject.start
        expect(subject.started).to eq(true)
      end

      it 'does not start StackProf again if already started' do
        StackProf.start
        subject.set_initial_sample_decision(true)
        expect(StackProf).to receive(:start).and_call_original

        subject.start
        expect(subject.started).to eq(false)
      end
    end
  end

  describe '#stop' do
    it 'does not stop StackProf if not sampled' do
      subject.set_initial_sample_decision(false)
      expect(StackProf).not_to receive(:stop)
      subject.stop
    end

    it 'does not stop StackProf if sampled but not started' do
      subject.set_initial_sample_decision(true)
      expect(StackProf).not_to receive(:stop)
      subject.stop
    end

    it 'stops StackProf if sampled and started' do
      subject.set_initial_sample_decision(true)
      subject.start
      expect(StackProf).to receive(:stop)
      subject.stop
    end
  end

  describe '#set_initial_sample_decision' do
    context 'with profiling disabled' do
      it 'does not sample when profiles_sample_rate is nil' do
        Sentry.configuration.profiles_sample_rate = nil

        subject.set_initial_sample_decision(true)
        expect(subject.sampled).to eq(false)
      end

      it 'does not sample when profiles_sample_rate is invalid' do
        Sentry.configuration.profiles_sample_rate = 5.0

        subject.set_initial_sample_decision(true)
        expect(subject.sampled).to eq(false)
      end
    end

    context 'with profiling enabled' do
      it 'does not sample when parent transaction is not sampled' do
        subject.set_initial_sample_decision(false)
        expect(subject.sampled).to eq(false)
      end

      it 'does not sample when profiles_sample_rate is 0' do
        Sentry.configuration.profiles_sample_rate = 0

        subject.set_initial_sample_decision(true)
        expect(subject.sampled).to eq(false)
      end

      it 'samples when profiles_sample_rate is 1' do
        subject.set_initial_sample_decision(true)
        expect(subject.sampled).to eq(true)
      end

      it 'uses profiles_sample_rate for sampling (positive result)' do
        Sentry.configuration.profiles_sample_rate = 0.5
        expect(Random).to receive(:rand).and_return(0.4)
        subject.set_initial_sample_decision(true)
        expect(subject.sampled).to eq(true)
      end

      it 'uses profiles_sample_rate for sampling (negative result)' do
        Sentry.configuration.profiles_sample_rate = 0.5
        expect(Random).to receive(:rand).and_return(0.6)
        subject.set_initial_sample_decision(true)
        expect(subject.sampled).to eq(false)
      end
    end
  end

  describe '#to_hash' do
    let (:transport) { Sentry.get_current_client.transport }

    context 'when not sampled' do
      before { subject.set_initial_sample_decision(false) }

      it 'returns nil' do
        expect(subject.to_hash).to eq({})
      end

      it 'records lost event' do
        expect(transport).to receive(:record_lost_event).with(:sample_rate, 'profile')
        subject.to_hash
      end
    end

    it 'returns nil unless started' do
      subject.set_initial_sample_decision(true)
      expect(subject.to_hash).to eq({})
    end

    context 'with empty results' do
      before do
        subject.set_initial_sample_decision(true)
        subject.start
        subject.stop
      end

      it 'returns empty' do
        expect(StackProf).to receive(:results).and_call_original
        expect(subject.to_hash).to eq({})
      end

      it 'records lost event' do
        expect(transport).to receive(:record_lost_event).with(:insufficient_data, 'profile')
        subject.to_hash
      end
    end

    context 'with insufficient samples' do
      let(:truncated_results) do
        results = stackprof_results
        frame = stackprof_results[:frames].keys.first
        results[:raw] = [1, frame, 2] # 2 samples with single frame
        results
      end

      before do
        allow(StackProf).to receive(:results).and_return(truncated_results)
        subject.set_initial_sample_decision(true)
        subject.start
        subject.stop
      end

      it 'returns empty' do
        expect(subject.to_hash).to eq({})
      end

      it 'records lost event' do
        expect(transport).to receive(:record_lost_event).with(:insufficient_data, 'profile')
        subject.to_hash
      end
    end

    context 'with profiled code' do
      before do
        allow(StackProf).to receive(:results).and_return(stackprof_results)
        subject.set_initial_sample_decision(true)
        subject.start
        subject.stop
      end

      it 'has correct attributes' do
        hash = subject.to_hash

        expect(hash[:event_id]).to eq(subject.event_id)
        expect(hash[:platform]).to eq('ruby')
        expect(hash[:version]).to eq('1')
        expect(hash[:profile]).to include(:frames, :stacks, :samples)
      end

      it 'has correct frames' do
        frames = subject.to_hash[:profile][:frames]

        foo_frame = frames.find { |f| f[:function] =~ /foo/ }
        expect(foo_frame[:function]).to eq('Foo.foo')
        expect(foo_frame[:module]).to eq('Bar')
        expect(foo_frame[:in_app]).to eq(true)
        expect(foo_frame[:lineno]).to eq(7)
        expect(foo_frame[:filename]).to eq('spec/sentry/profiler_spec.rb')
        expect(foo_frame[:abs_path]).to include('sentry-ruby/sentry-ruby/spec/sentry/profiler_spec.rb')

        bar_frame = frames.find { |f| f[:function] =~ /bar/ }
        expect(bar_frame[:function]).to eq('Bar.bar')
        expect(bar_frame[:module]).to eq(nil)
        expect(bar_frame[:in_app]).to eq(true)
        expect(bar_frame[:lineno]).to eq(12)
        expect(bar_frame[:filename]).to eq('spec/sentry/profiler_spec.rb')
        expect(bar_frame[:abs_path]).to include('sentry-ruby/sentry-ruby/spec/sentry/profiler_spec.rb')

        sleep_frame = frames.find { |f| f[:function] =~ /sleep/ }
        expect(sleep_frame[:function]).to eq('Kernel#sleep')
        expect(sleep_frame[:module]).to eq(nil)
        expect(sleep_frame[:in_app]).to eq(false)
        expect(sleep_frame[:lineno]).to eq(nil)
        expect(sleep_frame[:filename]).to eq('<cfunc>')
        expect(sleep_frame[:abs_path]).to include('<cfunc>')

        times_frame = frames.find { |f| f[:function] =~ /times/ }
        expect(times_frame[:function]).to eq('Integer#times')
        expect(times_frame[:module]).to eq(nil)
        expect(times_frame[:in_app]).to eq(false)
        expect(times_frame[:lineno]).to eq(nil)
        expect(times_frame[:filename]).to eq('<cfunc>')
        expect(times_frame[:abs_path]).to include('<cfunc>')
      end

      it 'has correct stacks' do
        profile = subject.to_hash[:profile]
        frames = profile[:frames]
        stacks = profile[:stacks]

        # look at tops, rest is ruby/rspec stuff
        stack_tops = stacks.map { |s| s.take(3) }.map { |s| s.map { |i| frames[i][:function] } }
        expect(stack_tops).to include(['Foo.foo', 'Integer#times', 'Foo.foo'])
        expect(stack_tops).to include(['Integer#times', 'Foo.foo', 'Bar.bar'])

        stack_tops2 = stack_tops.map { |s| s.take(2) }
        expect(stack_tops2).to include(['Kernel#sleep', 'Bar.bar'])
      end

      it 'has correct samples' do
        profile = subject.to_hash[:profile]
        num_stacks = profile[:stacks].size
        samples = profile[:samples]
        last_elapsed = 0

        samples.each do |sample|
          expect(sample[:thread_id]).to eq('0')
          expect(sample[:stack_id]).to be_between(0, num_stacks - 1)

          expect(sample[:elapsed_since_start_ns]).to be_a(String)
          elapsed = sample[:elapsed_since_start_ns].to_i
          expect(elapsed).to be > last_elapsed
          last_elapsed = elapsed
        end
      end
    end
  end
end
