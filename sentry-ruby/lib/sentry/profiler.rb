# frozen_string_literal: true

return unless defined?(StackProf)

require 'securerandom'

module Sentry
  class Profiler

    VERSION = '1'
    PLATFORM = 'ruby'
    # 101 Hz in microseconds
    DEFAULT_INTERVAL = 1e6 / 101

    attr_reader :sampled, :started, :event_id

    def initialize
      @event_id = SecureRandom.uuid.delete('-')
      @started = false
      @sampled = nil
    end

    def start
      return unless @sampled

      @started = StackProf.start(interval: DEFAULT_INTERVAL,
                                 mode: :wall,
                                 raw: true,
                                 aggregate: false)

      @started ? log('Started') : log('Not started since running elsewhere')
    end

    def stop
      return unless @sampled
      return unless @started

      StackProf.stop
      log('Stopped')
    end

    def profile_context
      { profile_id: @event_id }
    end

    # Sets initial sampling decision of the profile.
    # @return [void]
    def set_initial_sample_decision(transaction_sampled)
      unless Sentry.initialized? && Sentry.configuration.profiling_enabled?
        @sampled = false
        return
      end

      unless transaction_sampled
        @sampled = false
        log('Discarding profile because transaction not sampled')
        return
      end

      profiles_sample_rate = Sentry.configuration.profiles_sample_rate

      case profiles_sample_rate
      when 0.0
        @sampled = false
        log('Discarding profile because sample_rate is 0')
        return
      when 1.0
        @sampled = true
        return
      else
        @sampled = Random.rand < profiles_sample_rate
      end

      log('Discarding profile due to sampling decision') unless @sampled
    end

    def to_hash
      return nil unless Sentry.initialized?
      return nil unless @sampled
      return nil unless @started

      results = StackProf.results
      return nil unless results
      return nil if results.empty?
      return nil if results[:samples] == 0
      return nil unless results[:raw]

      frame_map = {}

      frames = results[:frames].to_enum.with_index.map do |frame, idx|
        frame_id, frame_data = frame

        # need to map over stackprof frame ids to ours
        frame_map[frame_id] = idx

        in_app = in_app?(frame_data[:file])
        filename = compute_filename(frame_data[:file], in_app)
        function, mod = split_module(frame_data[:name])

        {
          abs_path: frame_data[:file],
          function: function,
          module: mod,
          lineno: frame_data[:line],
          filename: filename,
          in_app: in_app
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
            # TODO-neel-profiler we need to patch rb_profile_frames and write our own C extension to enable threading info.
            # Till then, on multi-threaded servers like puma, we will get frames from other active threads when the one
            # we're profiling is idle/sleeping/waiting for IO etc.
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

    def project_root
      @project_root ||= Sentry.configuration.project_root
    end

    def in_app_pattern
      @in_app_pattern ||= begin
        app_dirs_pattern = Sentry.configuration.app_dirs_pattern || Backtrace::APP_DIRS_PATTERN
        Regexp.new("^(#{project_root}/)?#{app_dirs_pattern}")
      end
    end

    def in_app?(abs_path)
      abs_path.match?(in_app_pattern)
    end

    # copied from stacktrace.rb since I don't want to touch existing code
    # TODO-neel-profiler try to fetch this from stackprof once we patch
    # the native extension
    def compute_filename(abs_path, in_app)
      return nil if abs_path.nil?

      under_project_root = project_root && abs_path.start_with?(project_root)

      prefix =
        if under_project_root && in_app
          project_root
        else
          longest_load_path = $LOAD_PATH.select { |path| abs_path.start_with?(path.to_s) }.max_by(&:size)

          if under_project_root
            longest_load_path || project_root
          else
            longest_load_path
          end
        end

      prefix ? abs_path[prefix.to_s.chomp(File::SEPARATOR).length + 1..-1] : abs_path
    end

    def split_module(name)
      # last module plus class/instance method
      i = name.rindex('::')
      function = i ? name[(i + 2)..-1] : name
      mod = i ? name[0...i] : nil

      [function, mod]
    end
  end
end
