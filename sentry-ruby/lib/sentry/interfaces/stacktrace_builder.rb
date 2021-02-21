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

    def build(backtrace)
      parsed_lines = parse_backtrace_lines(backtrace).select(&:file)
      frames = parsed_lines.reverse.map do |line|
        convert_parsed_line_into_frame(line)
      end

      StacktraceInterface.new(frames)
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
