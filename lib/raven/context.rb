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

    def initialize(opts = {})
      @context = {
        :user => {},
        :tags => {},
        :rack => {},
        :extra => { :server => { :os => os_context, :runtime => runtime_context } }
      }
      @configuration = opts[:configuration]
      @event = opts[:event]
      self.transaction = []
    end

    private

    def sys
      @sys = Raven::System.new
    end

    # TODO: reduce to uname -svra
    def os_context
      {
        :name => sys.command("uname -s") || RbConfig::CONFIG["host_os"],
        :version => sys.command("uname -v"),
        :build => sys.command("uname -r"),
        :kernel_version => sys.command("uname -a") || sys.command("ver") # windows
      }
    end

    def runtime_context
      {
        :name => Kernel.const_defined?(:RUBY_ENGINE) ? RUBY_ENGINE : RbConfig::CONFIG["ruby_install_name"],
        :version => Kernel.const_defined?(:RUBY_DESCRIPTION) ? RUBY_DESCRIPTION : sys.command("ruby -v")
      }
    end
  end
end
