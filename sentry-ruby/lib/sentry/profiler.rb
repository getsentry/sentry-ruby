# frozen_string_literal: true

require 'etc'
require 'stackprof'
require 'securerandom'

module Sentry
  class Profiler

    VERSION = '1'
    PLATFORM = 'ruby'
    # 101 Hz in microseconds
    DEFAULT_INTERVAL = 1e6 / 101

    def initialize
      @event_id = SecureRandom.uuid.delete('-')
      @started = false
    end

    def start
      @started = StackProf.start(interval: DEFAULT_INTERVAL,
                                 mode: :wall,
                                 raw: true,
                                 aggregate: false)

      @started ? log('Started') : log('Not started since running elsewhere')
    end

    def stop
      return unless @started

      StackProf.stop
      log('Stopped')
    end

    def to_hash
      return nil unless Sentry.initialized?
      return nil unless @started

      results = StackProf.results
      return nil unless results
      return nil if results.empty?

      frame_map = {}

      frames = results[:frames].to_enum.with_index.map do |frame, idx|
        frame_id, frame_data = frame

        # need to map over stackprof frame ids to ours
        frame_map[frame_id] = idx

        # TODO-neel module, filename, in_app
        {
          abs_path: frame_data[:file],
          function: frame_data[:name],
          lineno: frame_data[:line]
        }.compact
      end

      idx = 0
      stacks = []
      num_seen = []

      # extract stacks from raw
      # raw is a single array of [.., len_stack, *stack_frames(len_stack), num_stack_seen , ..]
      while (len = results[:raw][idx])
        idx += 1

        # our call graph is reversed
        stack = results[:raw].slice(idx, len).map { |id| frame_map[id] }.compact.reverse
        stacks << stack

        num_seen << results[:raw][idx + len]
        idx += len + 1

        log('Unknown frame in stack') if stack.size != len
      end

      idx = 0
      elapsed_since_start_ns = 0
      samples = []

      num_seen.each_with_index do |n, i|
        n.times do
          # stackprof deltas are in microseconds
          delta = results[:raw_timestamp_deltas][idx]
          elapsed_since_start_ns += (delta * 1e3).to_i
          idx += 1

          # Not sure why but some deltas are very small like 0/1 values,
          # they pollute our flamegraph so just ignore them for now.
          # Open issue at https://github.com/tmm1/stackprof/issues/201
          next if delta < 10

          samples << {
            stack_id: i,
            # TODO-neel we need to patch rb_profile_frames and write our own C extension to enable threading info
            # till then, on multi-threaded servers like puma, we will get frames from other active threads when the one
            # we're profiling is idle/sleeping/waiting for IO etc
            # https://bugs.ruby-lang.org/issues/10602
            thread_id: '0',
            elapsed_since_start_ns: elapsed_since_start_ns.to_s
          }
        end
      end

      log('Some samples thrown away') if samples.size != results[:samples]

      if samples.size <= 2
        log('Not enough samples, discarding profiler')
        return nil
      end

      profile = {
        frames: frames,
        stacks: stacks,
        samples: samples
      }

      {
        event_id: @event_id,
        platform: PLATFORM,
        version: VERSION,
        profile: profile
      }
    end

    private

    def log(message)
      Sentry.logger.debug(LOGGER_PROGNAME) { "[Profiler] #{message}" }
    end

  end
end
