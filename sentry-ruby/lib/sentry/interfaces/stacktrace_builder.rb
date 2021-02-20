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
      parsed_backtrace_lines = Backtrace.parse(
        backtrace, project_root, app_dirs_pattern, &backtrace_cleanup_callback
      ).lines

      frames = []

      parsed_backtrace_lines.reverse.each_with_object(frames) do |line, frames|
        frame = convert_parsed_line_into_frame(line, project_root, linecache, context_lines)
        frames << frame if frame.filename
      end

      StacktraceInterface.new(frames)
    end

    def convert_parsed_line_into_frame(line, project_root, linecache, context_lines)
      frame = StacktraceInterface::Frame.new(project_root, line)
      frame.set_context(linecache, context_lines) if context_lines
      frame
    end
  end
end
