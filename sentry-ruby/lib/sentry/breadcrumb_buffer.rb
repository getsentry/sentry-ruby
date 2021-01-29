require "sentry/breadcrumb"

module Sentry
  class BreadcrumbBuffer
    include Enumerable

    attr_accessor :buffer

    def initialize(size = 100)
      @buffer = Array.new(size)
    end

    def record(crumb)
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
