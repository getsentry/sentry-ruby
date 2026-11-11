# frozen_string_literal: true

require "concurrent/map"

module Sentry
  # @api private
  class Backtrace
    # Handles backtrace parsing line by line
    class Line
      RB_EXTENSION = ".rb"
      CLASS_EXTENSION = ".class"
      # regexp (optional leading X: on windows, or JRuby9000 class-prefix)
      RUBY_INPUT_FORMAT = /
        ^ \s* (?: [a-zA-Z]: | uri:classloader: )? ([^:]+ | <.*>):
        (\d+)
        (?: :in\s('|`)(?:([\w:]+)\#)?([^']+)')?$
      /x

      # org.jruby.runtime.callsite.CachingCallSite.call(CachingCallSite.java:170)
      JAVA_INPUT_FORMAT = /^([\w$.]+)\.([\w$]+)\(([\w$.]+):(\d+)\)$/

      # The file portion of the line (such as app/models/user.rb)
      attr_reader :file

      # The line number portion of the line
      attr_reader :number

      # The method of the line (such as index)
      attr_reader :method

      # The module name (JRuby)
      attr_reader :module_name

      attr_reader :in_app_pattern

      # Parsed [file, number, method, module_name] by raw backtrace line.
      # A recurring error produces the same lines on every capture, so a hit
      # skips the regex match and its substring allocations. Parsing doesn't
      # depend on in_app_pattern, so the pattern isn't part of the key.
      # The cache is cleared once it reaches PARSE_CACHE_LIMIT entries.
      PARSE_CACHE_LIMIT = 4096
      @parse_cache = Concurrent::Map.new

      # Parses a single line of a given backtrace
      # @param [String] unparsed_line The raw line from +caller+ or some backtrace
      # @return [Line] The parsed backtrace line
      def self.parse(unparsed_line, in_app_pattern = nil)
        file, number, method, module_name = @parse_cache[unparsed_line] || parse_and_cache(unparsed_line)
        new(file, number, method, module_name, in_app_pattern)
      end

      # The parsed strings are shared by every Line (and event frame) created
      # from the same raw line, so they're frozen to keep one caller's in-place
      # mutation from leaking into later events.
      def self.parse_and_cache(unparsed_line)
        ruby_match = unparsed_line.match(RUBY_INPUT_FORMAT)

        if ruby_match
          file = ruby_match[1]
          number = ruby_match[2]
          module_name = ruby_match[4]
          method = ruby_match[5]
          if file.end_with?(CLASS_EXTENSION)
            file.sub!(/\.class$/, RB_EXTENSION)
          end
        else
          java_match = unparsed_line.match(JAVA_INPUT_FORMAT)
          if java_match
            module_name = java_match[1]
            method = java_match[2]
            file = java_match[3]
            number = java_match[4]
          end
        end

        parsed = [file&.freeze, number&.freeze, method&.freeze, module_name&.freeze].freeze
        @parse_cache.clear if @parse_cache.size >= PARSE_CACHE_LIMIT
        @parse_cache[unparsed_line] = parsed
      end
      private_class_method :parse_and_cache

      # Creates a Line from a Thread::Backtrace::Location object
      # This is more efficient than converting to string and parsing with regex
      # @param [Thread::Backtrace::Location] location The location object
      # @param [Regexp, nil] in_app_pattern Optional pattern to determine if the line is in-app
      # @return [Line] The backtrace line
      def self.from_source_location(location, in_app_pattern = nil)
        file = location.absolute_path
        number = location.lineno
        method = location.base_label

        label = location.label
        index = label.index("#") || label.index(".")
        module_name = label[0, index] if index

        new(file, number, method, module_name, in_app_pattern)
      end

      def initialize(file, number, method, module_name, in_app_pattern)
        @file = file
        @module_name = module_name
        @number = number.to_i
        @method = method
        @in_app_pattern = in_app_pattern
      end

      def in_app
        return false unless in_app_pattern
        return false unless file

        file.match?(in_app_pattern)
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
  end
end
