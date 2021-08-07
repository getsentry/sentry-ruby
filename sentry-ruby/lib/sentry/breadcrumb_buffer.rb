require "sentry/breadcrumb"

module Sentry
  class BreadcrumbBuffer
    DEFAULT_SIZE = 100
    DEFAULT_LOG_LEVEL = :debug
    LEVELS = %w[debug info warn error fatal].freeze

    include Enumerable

    attr_accessor :buffer

    def initialize(size = nil, log_level = nil)
      @buffer = Array.new(size || DEFAULT_SIZE)
      @log_level_index = LEVELS.find_index((log_level || DEFAULT_LOG_LEVEL).to_s.downcase)
    end

    def record(crumb)
      return if !crumb.level.nil? && LEVELS.find_index(crumb.level.to_s.downcase) < @log_level_index

      yield(crumb) if block_given?
      @buffer.slice!(0)
      @buffer << crumb
    end

    def members
      @buffer.compact
    end

    def peek
      members.last
    end

    def each(&block)
      members.each(&block)
    end

    def empty?
      members.none?
    end

    def to_hash
      {
        values: members.map(&:to_hash)
      }
    end

    def dup
      copy = super
      copy.buffer = buffer.deep_dup
      copy
    end
  end
end
