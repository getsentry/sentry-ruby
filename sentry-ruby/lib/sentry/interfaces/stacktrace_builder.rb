module Sentry
  class StacktraceBuilder
    attr_reader :project_root, :app_dirs_pattern, :linecache, :context_lines, :backtrace_cleanup_callback

    def initialize(project_root:, app_dirs_pattern:, linecache:, context_lines:, backtrace_cleanup_callback: nil)
      @project_root = project_root
      @app_dirs_pattern = app_dirs_pattern
      @linecache = linecache
      @context_lines = context_lines
      @backtrace_cleanup_callback = backtrace_cleanup_callback
    end

    # you can pass a block to customize/exclude frames:
    #
    # ```ruby
    # builder.build(backtrace) do |frame|
    #   if frame.module.match?(/a_gem/)
    #     nil
    #   else
    #     frame
    #   end
    # end
    # ```
    def build(backtrace:, &frame_callback)
      parsed_lines = parse_backtrace_lines(backtrace).select(&:file)

      frames = parsed_lines.reverse.map do |line|
        frame = convert_parsed_line_into_frame(line)
        frame = frame_callback.call(frame) if frame_callback
        frame
      end.compact

      StacktraceInterface.new(frames: frames)
    end

    private

    def convert_parsed_line_into_frame(line)
      frame = StacktraceInterface::Frame.new(project_root, line)
      frame.set_context(linecache, context_lines) if context_lines
      frame
    end

    def parse_backtrace_lines(backtrace)
      Backtrace.parse(
        backtrace, project_root, app_dirs_pattern, &backtrace_cleanup_callback
      ).lines
    end
  end
end
