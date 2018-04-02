require 'rbconfig'

module Raven
  class Context
    def self.current
      Thread.current[:sentry_context] ||= new
    end

    def self.clear!
      Thread.current[:sentry_context] = nil
    end

    attr_accessor :transaction

    %w(extra user tags rack).each do |ctx_type|
      define_method(ctx_type) { @context[ctx_type.to_sym] }
      define_method(ctx_type + "=") { |hash| @context[ctx_type.to_sym].merge!(hash || {}) }
      alias_method (ctx_type + "_context").to_sym, (ctx_type + "=").to_sym
    end

    def initialize
      @context = { :user => {}, :tags => {}, :rack => {}, :extra => {} }
      self.transaction = []
    end
  end

  class ContextCollector
    def initialize(event, instance, config)
      raise ArgumentError unless [event, instance, config].all? { |ctx| ctx.is_a?(Raven::Context) }
      @event = event
      @instance = instance
      @config = config
    end

    def user
      @config.user.merge(@instance.user).merge(@event.user)
    end

    def tags
      @config.tags.merge(@instance.tags).merge(@event.tags)
    end

    def extra
      @config.extra.merge(@instance.extra).merge(@event.extra)
    end

    def transaction
      if @event.transaction.empty?
        @instance.transaction.last
      else
        @event.transaction.last
      end
    end
  end
end
