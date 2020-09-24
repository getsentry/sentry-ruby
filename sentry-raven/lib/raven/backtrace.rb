# frozen_string_literal: true

## Inspired by Rails' and Airbrake's backtrace parsers.

module Raven
  # Front end to parsing the backtrace for each notice
  class Backtrace
    # Handles backtrace parsing line by line
    class Line
      RB_EXTENSION = ".rb"
      # regexp (optional leading X: on windows, or JRuby9000 class-prefix)
      RUBY_INPUT_FORMAT = /
        ^ \s* (?: [a-zA-Z]: | uri:classloader: )? ([^:]+ | <.*>):
        (\d+)
        (?: :in \s `([^']+)')?$
      /x.freeze

      # org.jruby.runtime.callsite.CachingCallSite.call(CachingCallSite.java:170)
      JAVA_INPUT_FORMAT = /^(.+)\.([^\.]+)\(([^\:]+)\:(\d+)\)$/.freeze

      # The file portion of the line (such as app/models/user.rb)
      attr_reader :file

      # The line number portion of the line
      attr_reader :number

      # The method of the line (such as index)
      attr_reader :method

      # The module name (JRuby)
      attr_reader :module_name

      # Parses a single line of a given backtrace
      # @param [String] unparsed_line The raw line from +caller+ or some backtrace
      # @return [Line] The parsed backtrace line
      def self.parse(unparsed_line)
        ruby_match = unparsed_line.match(RUBY_INPUT_FORMAT)
        if ruby_match
          _, file, number, method = ruby_match.to_a
          file.sub!(/\.class$/, RB_EXTENSION)
          module_name = nil
        else
          java_match = unparsed_line.match(JAVA_INPUT_FORMAT)
          _, module_name, method, file, number = java_match.to_a
        end
        new(file, number, method, module_name)
      end

      def initialize(file, number, method, module_name)
        self.file = file
        self.module_name = module_name
        self.number = number.to_i
        self.method = method
      end

      def in_app
        if file =~ self.class.in_app_pattern
          true
        else
          false
        end
      end

      # Reconstructs the line in a readable fashion
      def to_s
        "#{file}:#{number}:in `#{method}'"
      end

      def ==(other)
        to_s == other.to_s
      end

      def inspect
        "<Line:#{self}>"
      end

      def self.in_app_pattern
        @in_app_pattern ||= begin
          project_root = Raven.configuration.project_root&.to_s
          Regexp.new("^(#{project_root}/)?#{Raven.configuration.app_dirs_pattern || APP_DIRS_PATTERN}")
        end
      end

      private

      attr_writer :file, :number, :method, :module_name
    end

    APP_DIRS_PATTERN = /(bin|exe|app|config|lib|test)/.freeze

    # holder for an Array of Backtrace::Line instances
    attr_reader :lines

    def self.parse(backtrace, opts = {})
      ruby_lines = backtrace.is_a?(Array) ? backtrace : backtrace.split(/\n\s*/)

      ruby_lines = opts[:configuration].backtrace_cleanup_callback.call(ruby_lines) if opts[:configuration]&.backtrace_cleanup_callback

      filters = opts[:filters] || []
      filtered_lines = ruby_lines.to_a.map do |line|
        filters.reduce(line) do |nested_line, proc|
          proc.call(nested_line)
        end
      end.compact

      lines = filtered_lines.map do |unparsed_line|
        Line.parse(unparsed_line)
      end

      new(lines)
    end

    def initialize(lines)
      self.lines = lines
    end

    def inspect
      "<Backtrace: " + lines.map(&:inspect).join(", ") + ">"
    end

    def to_s
      content = []
      lines.each do |line|
        content << line
      end
      content.join("\n")
    end

    def ==(other)
      if other.respond_to?(:lines)
        lines == other.lines
      else
        false
      end
    end

    private

    attr_writer :lines
  end
end
