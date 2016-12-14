require 'raven/interface'

module Raven
  class StacktraceInterface < Interface
    attr_accessor :frames

    def initialize(*arguments)
      self.frames = []
      super(*arguments)
    end

    def self.sentry_alias
      :stacktrace
    end

    def to_hash(*args)
      data = super(*args)
      data[:frames] = data[:frames].map(&:to_hash)
      data
    end

    def self.from_backtrace(backtrace, linecache, context_lines = nil)
      backtrace = Backtrace.parse(backtrace)
      int = new
      backtrace.lines.reverse_each do |line|
        frame = StacktraceInterface::Frame.from_backtrace_line(line, linecache, context_lines)
        int.frames << frame if frame.filename
      end

      int
    end

    # Not actually an interface, but I want to use the same style
    class Frame < Interface
      attr_accessor :abs_path
      attr_accessor :function
      attr_accessor :vars
      attr_accessor :pre_context
      attr_accessor :post_context
      attr_accessor :context_line
      attr_accessor :module
      attr_accessor :lineno
      attr_accessor :in_app

      def initialize(*arguments)
        self.vars, self.pre_context, self.post_context = [], [], []
        super(*arguments)
      end

      def self.from_backtrace_line(line, linecache, context_lines)
        frame = new
        frame.abs_path = line.file if line.file
        frame.function = line.method if line.method
        frame.lineno = line.number
        frame.in_app = line.in_app
        frame.module = line.module_name if line.module_name

        if context_lines && frame.abs_path
          frame.pre_context, frame.context_line, frame.post_context = \
            linecache.get_file_context(frame.abs_path, frame.lineno, context_lines)
        end

        frame
      end

      def filename
        return if abs_path.nil?

        prefix =
          if under_project_root? && in_app
            project_root
          elsif under_project_root?
            longest_load_path || project_root
          else
            longest_load_path
          end

        prefix ? abs_path[prefix.to_s.chomp(File::SEPARATOR).length + 1..-1] : abs_path
      end

      def under_project_root?
        project_root && abs_path.start_with?(project_root)
      end

      def project_root
        @project_root ||= Raven.configuration.project_root && Raven.configuration.project_root.to_s
      end

      def longest_load_path
        @longest_load_path ||= $LOAD_PATH.select { |s| abs_path.start_with?(s) }.max_by(&:length)
      end

      def to_hash(*args)
        data = super(*args)
        data[:filename] = filename
        data.delete(:vars) unless vars && !vars.empty?
        data.delete(:pre_context) unless pre_context && !pre_context.empty?
        data.delete(:post_context) unless post_context && !post_context.empty?
        data.delete(:context_line) unless context_line && !context_line.empty?
        data
      end
    end
  end
end
