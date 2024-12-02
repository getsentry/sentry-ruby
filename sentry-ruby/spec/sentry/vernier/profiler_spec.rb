# frozen_string_literal: true

require "spec_helper"

require "sentry/vernier/profiler"

RSpec.describe Sentry::Vernier::Profiler, when: { ruby_version?: [:>=, "3.2.1"] } do
  subject(:profiler) { described_class.new(Sentry.configuration) }

  before do
    # TODO: replace with some public API once available
    Vernier.stop_profile if Vernier.instance_variable_get(:@collector)

    perform_basic_setup do |config|
      config.traces_sample_rate = traces_sample_rate
      config.profiles_sample_rate = profiles_sample_rate
      config.app_dirs_pattern = %r{spec/support}
    end
  end

  let(:profiles_sample_rate) { 1.0 }
  let(:traces_sample_rate) { 1.0 }

  describe '#start' do
    context "when profiles_sample_rate is 0" do
      let(:profiles_sample_rate) { 0.0 }

      it "does not start Vernier" do
        profiler.set_initial_sample_decision(true)

        expect(Vernier).not_to receive(:start_profile)
        profiler.start
        expect(profiler.started).to eq(false)
      end
    end

    context "when profiles_sample_rate is between 0.0 and 1.0" do
      let(:profiles_sample_rate) { 0.4 }

      it "randomizes profiling" do
        profiler.set_initial_sample_decision(true)

        expect([nil, true]).to include(profiler.start)
      end
    end

    context "when traces_sample_rate is nil" do
      let(:traces_sample_rate) { nil }

      it "does not start Vernier" do
        profiler.set_initial_sample_decision(true)

        expect(Vernier).not_to receive(:start_profile)
        profiler.start
        expect(profiler.started).to eq(false)
      end
    end

    context 'without sampling decision' do
      it 'does not start Vernier' do
        expect(Vernier).not_to receive(:start_profile)
        profiler.start
        expect(profiler.started).to eq(false)
      end

      it 'does not start Vernier if not sampled' do
        expect(Vernier).not_to receive(:start_profile)
        profiler.start
        expect(profiler.started).to eq(false)
      end
    end

    context 'with sampling decision' do
      before do
        profiler.set_initial_sample_decision(true)
      end

      it 'starts Vernier if sampled' do
        expect(Vernier).to receive(:start_profile).and_return(true)

        profiler.start

        expect(profiler.started).to eq(true)
      end

      it 'does not start Vernier again if already started' do
        expect(Vernier).to receive(:start_profile).and_return(true).once

        profiler.start
        profiler.start

        expect(profiler.started).to be(true)
      end
    end

    context "when Vernier crashes" do
      it "logs the error and does not raise" do
        profiler.set_initial_sample_decision(true)

        expect(Vernier).to receive(:start_profile).and_raise("boom")

        expect { profiler.start }.to_not raise_error("boom")
      end

      it "doesn't start if Vernier raises that it already started" do
        profiler.set_initial_sample_decision(true)

        expect(Vernier).to receive(:start_profile).and_raise(RuntimeError.new("Profile already started"))

        profiler.start

        expect(profiler.started).to eq(false)
      end
    end
  end

  describe '#stop' do
    it 'does not stop Vernier if not sampled' do
      profiler.set_initial_sample_decision(false)
      expect(Vernier).not_to receive(:stop_profile)
      profiler.stop
    end

    it 'does not stop Vernier if sampled but not started' do
      profiler.set_initial_sample_decision(true)
      expect(Vernier).not_to receive(:stop_profile)
      profiler.stop
    end

    it 'stops Vernier if sampled and started' do
      profiler.set_initial_sample_decision(true)
      profiler.start
      expect(Vernier).to receive(:stop_profile)
      profiler.stop
    end

    it 'does not crash when Vernier was already stopped' do
      profiler.set_initial_sample_decision(true)
      profiler.start
      Vernier.stop_profile
      profiler.stop
    end

    it 'does not crash when stopping Vernier crashed' do
      profiler.set_initial_sample_decision(true)
      profiler.start
      expect(Vernier).to receive(:stop_profile).and_raise(RuntimeError.new("Profile not started"))
      profiler.stop
    end
  end

  describe "#to_hash" do
    let (:transport) { Sentry.get_current_client.transport }


    it "records lost event if not sampled" do
      expect(transport).to receive(:record_lost_event).with(:sample_rate, "profile")

      profiler.set_initial_sample_decision(true)
      profiler.start
      profiler.set_initial_sample_decision(false)

      expect(profiler.to_hash).to eq({})
    end
  end

  context 'with sampling decision' do
    before do
      profiler.set_initial_sample_decision(true)
    end

    describe '#to_hash' do
      it "returns empty hash if not started" do
        expect(profiler.to_hash).to eq({})
      end

      context 'with single-thread profiled code' do
        before do
          profiler.start
          ProfilerTest::Bar.bar
          profiler.stop
        end

        it 'has correct frames' do
          frames = profiler.to_hash[:profile][:frames]

          foo_frame = frames.find { |f| f[:function] =~ /foo/ }

          expect(foo_frame[:function]).to eq('Foo.foo')
          expect(foo_frame[:module]).to eq('ProfilerTest::Bar')
          expect(foo_frame[:in_app]).to eq(true)
          expect(foo_frame[:lineno]).to eq(6)
          expect(foo_frame[:filename]).to eq('spec/support/profiler.rb')
          expect(foo_frame[:abs_path]).to include('sentry-ruby/sentry-ruby/spec/support/profiler.rb')
        end

        it 'has correct stacks' do
          profile = profiler.to_hash[:profile]
          frames = profile[:frames]
          stacks = profile[:stacks]

          stack_tops = stacks.map { |s| s.take(3) }.map { |s| s.map { |i| frames[i][:function] } }

          expect(stack_tops.any? { |tops| tops.include?("Foo.foo") }).to be(true)
          expect(stack_tops.any? { |tops| tops.include?("Bar.bar") }).to be(true)
          expect(stack_tops.any? { |tops| tops.include?("Integer#times") }).to be(true)

          stacks.each do |stack|
            stack.each do |frame_idx|
              expect(frames[frame_idx][:function]).to be_a(String)
            end
          end
        end

        it 'has correct samples' do
          profile = profiler.to_hash[:profile]
          samples = profile[:samples]
          last_elapsed = 0

          samples.group_by { |sample| sample[:thread_id] }.each do |thread_id, thread_samples|
            expect(thread_id.to_i).to be > 0

            last_elapsed = 0

            thread_samples.each do |sample|
              expect(sample[:stack_id]).to be > 0

              elapsed = sample[:elapsed_since_start_ns].to_i

              expect(elapsed).to be > 0.0
              expect(elapsed).to be > last_elapsed

              last_elapsed = elapsed
            end
          end
        end
      end

      context 'with multi-thread profiled code' do
        before do
          profiler.start

          2.times.map do |i|
            Thread.new do
              Thread.current.name = "thread-bar-#{i}"

              ProfilerTest::Bar.bar
            end
          end.map(&:join)

          profiler.stop
        end

        it "has correct thread metadata" do
          thread_metadata = profiler.to_hash[:profile][:thread_metadata]

          main_thread = thread_metadata.values.find { |metadata| metadata[:name].include?("rspec") }
          thread1 = thread_metadata.values.find { |metadata| metadata[:name] == "thread-bar-0" }
          thread2 = thread_metadata.values.find { |metadata| metadata[:name] == "thread-bar-1" }

          thread_metadata.each do |thread_id, metadata|
            expect(thread_id.to_i).to be > 0
          end

          expect(main_thread[:name]).to include("rspec")
          expect(thread1[:name]).to eq("thread-bar-0")
          expect(thread2[:name]).to eq("thread-bar-1")
        end

        it 'has correct frames', when: { ruby_version?: [:>=, "3.3"] } do
          frames = profiler.to_hash[:profile][:frames]

          foo_frame = frames.find { |f| f[:function] =~ /foo/ }

          expect(foo_frame[:function]).to eq('Foo.foo')
          expect(foo_frame[:module]).to eq('ProfilerTest::Bar')
          expect(foo_frame[:in_app]).to eq(true)
          expect(foo_frame[:lineno]).to eq(6)
          expect(foo_frame[:filename]).to eq('spec/support/profiler.rb')
          expect(foo_frame[:abs_path]).to include('sentry-ruby/sentry-ruby/spec/support/profiler.rb')
        end

        it 'has correct stacks', when: { ruby_version?: [:>=, "3.3"] } do
          profile = profiler.to_hash[:profile]
          frames = profile[:frames]
          stacks = profile[:stacks]

          stack_tops = stacks.map { |s| s.take(3) }.map { |s| s.map { |i| frames[i][:function] } }

          expect(stack_tops.any? { |tops| tops.include?("Foo.foo") }).to be(true)
          expect(stack_tops.any? { |tops| tops.include?("Bar.bar") }).to be(true)
          expect(stack_tops.any? { |tops| tops.include?("Integer#times") }).to be(true)

          stacks.each do |stack|
            stack.each do |frame_idx|
              expect(frames[frame_idx][:function]).to be_a(String)
            end
          end
        end

        it 'has correct samples' do
          profile = profiler.to_hash[:profile]
          samples = profile[:samples]

          samples.group_by { |sample| sample[:thread_id] }.each do |thread_id, thread_samples|
            expect(thread_id.to_i).to be > 0

            last_elapsed = 0

            thread_samples.each do |sample|
              expect(sample[:stack_id]).to be > 0

              elapsed = sample[:elapsed_since_start_ns].to_i

              expect(elapsed).to be > 0.0
              expect(elapsed).to be > last_elapsed

              last_elapsed = elapsed
            end
          end
        end
      end
    end
  end
end
