module Raven
  class StacktraceInterface < Interface
    attr_accessor :frames

    def initialize(*arguments)
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

    # Not actually an interface, but want to use the same style
    class Frame < Interface
      attr_accessor :context_line, :function, :module, :pre_context, :post_context,
                    :vars, :filename, :abs_path, :lineno, :line, :in_app

      def initialize(*arguments)
        super(*arguments)
        self.abs_path = line.absolute_path
        self.lineno = line.lineno
        self.filename = line.path
        self.function = line.to_s.match(/`(.*)'/).captures[0]
      end

      def to_hash(*args)
        data = super(*args)
        data[:line] = nil # Remove the line object

        data
      end

      # Note that backtrace is Exception#backtrace_locations
      def self.from_backtrace(backtrace, configuration)
        backtrace.select(&:path).reverse!.map do |line|
          Frame.new do |frame|
            frame.line = line
            frame.in_app = configuration.in_app?(frame.abs_path)

            if configuration.context_lines
              frame.pre_context, frame.context_line, frame.post_context = \
                configuration.linecache.get_file_context(frame.abs_path, frame.lineno, configuration.context_lines)
            end
          end
        end
      end
    end
  end
end
