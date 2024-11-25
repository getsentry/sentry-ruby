# frozen_string_literal: true

require "rubygems"

module Sentry
  # @api private
  class Backtrace
    # Handles backtrace parsing line by line
    class Line
      RB_EXTENSION = ".rb"
      # regexp (optional leading X: on windows, or JRuby9000 class-prefix)
      RUBY_INPUT_FORMAT = /
        ^ \s* (?: [a-zA-Z]: | uri:classloader: )? ([^:]+ | <.*>):
        (\d+)
        (?: :in\s('|`)([^']+)')?$
      /x

      # org.jruby.runtime.callsite.CachingCallSite.call(CachingCallSite.java:170)
      JAVA_INPUT_FORMAT = /^(.+)\.([^\.]+)\(([^\:]+)\:(\d+)\)$/

      # The absolute path in the backtrace
      attr_reader :abs_path

      # The file portion of the line (such as app/models/user.rb)
      attr_reader :file

      # The line number portion of the line
      attr_reader :number

      # The method of the line (such as index)
      attr_reader :method

      # The module name (JRuby)
      attr_reader :module_name

      attr_reader :in_app_pattern

      # Parses a single line of a given backtrace
      # @param [String] unparsed_line The raw line from +caller+ or some backtrace
      # @return [Line] The parsed backtrace line
      def self.parse(unparsed_line, in_app_pattern = nil, cleaned_line = nil)
        ruby_match = unparsed_line.match(RUBY_INPUT_FORMAT)
        if ruby_match
          _, abs_path, number, _, method = ruby_match.to_a
          abs_path.sub!(/\.class$/, RB_EXTENSION)
          module_name = nil

          cleaned_match = cleaned_line.match(RUBY_INPUT_FORMAT) if cleaned_line
          if cleaned_match
            # prefer data from cleaned line
            _, file, number, _, method = cleaned_match.to_a
            file.sub!(/\.class$/, RB_EXTENSION)
          end
        else
          java_match = unparsed_line.match(JAVA_INPUT_FORMAT)
          _, module_name, method, abs_path, number = java_match.to_a


          cleaned_match = cleaned_line.match(JAVA_INPUT_FORMAT) if cleaned_line
          # prefer data from cleaned line
          _, module_name, method, file, number = cleaned_match.to_a if cleaned_match
        end

        new(abs_path, number, method, module_name, in_app_pattern, file || abs_path)
      end

      def initialize(abs_path, number, method, module_name, in_app_pattern, file = nil)
        @abs_path = abs_path
        @module_name = module_name
        @number = number.to_i
        @method = method
        @in_app_pattern = in_app_pattern
        @file = file
      end

      def in_app
        return false unless in_app_pattern

        if abs_path =~ in_app_pattern
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
    end

    # holder for an Array of Backtrace::Line instances
    attr_reader :lines

    def self.parse(backtrace, project_root, app_dirs_pattern, &backtrace_cleanup_callback)
      ruby_lines = backtrace.is_a?(Array) ? backtrace : backtrace.split(/\n\s*/)

      cleaned_lines = backtrace_cleanup_callback ? backtrace_cleanup_callback.call(ruby_lines) : []

      in_app_pattern ||= begin
        Regexp.new("^(#{project_root}/)?#{app_dirs_pattern}")
      end

      lines = ruby_lines.to_a.zip(cleaned_lines).map do |unparsed_line, cleaned_line|
        Line.parse(unparsed_line, in_app_pattern, cleaned_line)
      end

      new(lines)
    end

    def initialize(lines)
      @lines = lines
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
  end
end
