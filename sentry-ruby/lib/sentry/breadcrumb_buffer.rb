require "sentry/breadcrumb"

module Sentry
  class BreadcrumbBuffer
    include Enumerable

    attr_accessor :buffer

    def self.current
      Thread.current[:sentry_breadcrumbs] ||= new
    end

    def self.clear!
      Thread.current[:sentry_breadcrumbs] = nil
    end

    def initialize(size = 100)
      @buffer = Array.new(size)
    end

    def record(crumb = nil)
      if block_given?
        crumb = Breadcrumb.new if crumb.nil?
        yield(crumb)
      end
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
        :values => members.map(&:to_hash)
      }
    end
  end
end
