require "sentry/breadcrumb_buffer"
require "etc"

module Sentry
  class Scope
    include ArgumentCheckingHelper

    ATTRIBUTES = [:transaction_names, :contexts, :extra, :tags, :user, :level, :breadcrumbs, :fingerprint, :event_processors, :rack_env, :span]

    attr_reader(*ATTRIBUTES)

    def initialize(max_breadcrumbs: nil)
      @max_breadcrumbs = max_breadcrumbs
      set_default_value
    end

    def clear
      set_default_value
    end

    def apply_to_event(event, hint = nil)
      event.tags = tags.merge(event.tags)
      event.user = user.merge(event.user)
      event.extra = extra.merge(event.extra)
      event.contexts = contexts.merge(event.contexts)
      event.transaction = transaction_name if transaction_name

      if span
        event.contexts[:trace] = span.get_trace_context
      end

      event.fingerprint = fingerprint
      event.level = level
      event.breadcrumbs = breadcrumbs
      event.rack_env = rack_env if rack_env

      unless @event_processors.empty?
        @event_processors.each do |processor_block|
          event = processor_block.call(event, hint)
        end
      end

      event
    end

    def add_breadcrumb(breadcrumb)
      breadcrumbs.record(breadcrumb)
    end

    def clear_breadcrumbs
      set_new_breadcrumb_buffer
    end

    def dup
      copy = super
      copy.breadcrumbs = breadcrumbs.dup
      copy.contexts = contexts.deep_dup
      copy.extra = extra.deep_dup
      copy.tags = tags.deep_dup
      copy.user = user.deep_dup
      copy.transaction_names = transaction_names.deep_dup
      copy.fingerprint = fingerprint.deep_dup
      copy.span = span.deep_dup
      copy
    end

    def update_from_scope(scope)
      self.breadcrumbs = scope.breadcrumbs
      self.contexts = scope.contexts
      self.extra = scope.extra
      self.tags = scope.tags
      self.user = scope.user
      self.transaction_names = scope.transaction_names
      self.fingerprint = scope.fingerprint
      self.span = scope.span
    end

    def update_from_options(
      contexts: nil,
      extra: nil,
      tags: nil,
      user: nil,
      level: nil,
      fingerprint: nil
    )
      self.contexts.merge!(contexts) if contexts
      self.extra.merge!(extra) if extra
      self.tags.merge!(tags) if tags
      self.user = user if user
      self.level = level if level
      self.fingerprint = fingerprint if fingerprint
    end

    def set_rack_env(env)
      env = env || {}
      @rack_env = env
    end

    def set_span(span)
      check_argument_type!(span, Span)
      @span = span
    end

    def set_user(user_hash)
      check_argument_type!(user_hash, Hash)
      @user = user_hash
    end

    def set_extras(extras_hash)
      check_argument_type!(extras_hash, Hash)
      @extra.merge!(extras_hash)
    end

    def set_extra(key, value)
      @extra.merge!(key => value)
    end

    def set_tags(tags_hash)
      check_argument_type!(tags_hash, Hash)
      @tags.merge!(tags_hash)
    end

    def set_tag(key, value)
      @tags.merge!(key => value)
    end

    def set_contexts(contexts_hash)
      check_argument_type!(contexts_hash, Hash)
      @contexts.merge!(contexts_hash)
    end

    def set_context(key, value)
      check_argument_type!(value, Hash)
      @contexts.merge!(key => value)
    end

    def set_level(level)
      @level = level
    end

    def set_transaction_name(transaction_name)
      @transaction_names << transaction_name
    end

    def transaction_name
      @transaction_names.last
    end

    def get_transaction
      span.transaction if span
    end

    def get_span
      span
    end

    def set_fingerprint(fingerprint)
      check_argument_type!(fingerprint, Array)

      @fingerprint = fingerprint
    end

    def add_event_processor(&block)
      @event_processors << block
    end

    protected

    # for duplicating scopes internally
    attr_writer(*ATTRIBUTES)

    private

    def set_default_value
      @contexts = { :os => self.class.os_context, :runtime => self.class.runtime_context }
      @extra = {}
      @tags = {}
      @user = {}
      @level = :error
      @fingerprint = []
      @transaction_names = []
      @event_processors = []
      @rack_env = {}
      @span = nil
      set_new_breadcrumb_buffer
    end

    def set_new_breadcrumb_buffer
      @breadcrumbs = BreadcrumbBuffer.new(@max_breadcrumbs)
    end


    class << self
      def os_context
        @os_context ||=
          begin
            uname = Etc.uname
            {
              name: uname[:sysname] || RbConfig::CONFIG["host_os"],
              version: uname[:version],
              build: uname[:release],
              kernel_version: uname[:version]
            }
          end
      end

      def runtime_context
        @runtime_context ||= {
          name: RbConfig::CONFIG["ruby_install_name"],
          version: RUBY_DESCRIPTION || Sentry.sys_command("ruby -v")
        }
      end
    end

  end
end
