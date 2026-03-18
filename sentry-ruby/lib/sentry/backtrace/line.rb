# frozen_string_literal: true

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

      # Cache parsed Line data (file, number, method, module_name) by unparsed line string.
      # Same backtrace lines appear repeatedly (same code paths, same errors).
      # Values are frozen arrays to avoid mutation.
      # Limited to 2048 entries to prevent unbounded memory growth.
      PARSE_CACHE_LIMIT = 2048
      @parse_cache = {}

      # Cache complete Line objects by (unparsed_line, in_app_pattern) to avoid
      # re-creating identical Line objects across exceptions.
      @line_object_cache = {}

      # Parses a single line of a given backtrace
      # @param [String] unparsed_line The raw line from +caller+ or some backtrace
      # @return [Line] The parsed backtrace line
      def self.parse(unparsed_line, in_app_pattern = nil)
        # Try full Line object cache first (avoids creating new objects entirely)
        object_cache_key = unparsed_line
        pattern_cache = @line_object_cache[object_cache_key]
        if pattern_cache
          cached_line = pattern_cache[in_app_pattern]
          return cached_line if cached_line
        end

        cached = @parse_cache[unparsed_line]
        unless cached
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
          cached = [file, number, method, module_name].freeze
          @parse_cache.clear if @parse_cache.size >= PARSE_CACHE_LIMIT
          @parse_cache[unparsed_line] = cached
        end

        line = new(cached[0], cached[1], cached[2], cached[3], in_app_pattern)

        # Cache the Line object — limited by parse cache limit
        if @line_object_cache.size >= PARSE_CACHE_LIMIT
          @line_object_cache.clear
        end
        pattern_cache = (@line_object_cache[object_cache_key] ||= {})
        pattern_cache[in_app_pattern] = line

        line
      end

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
