# frozen_string_literal: true

require "sentry/breadcrumb_buffer"
require "etc"

module Sentry
  class Scope
    include ArgumentCheckingHelper

    ATTRIBUTES = [
      :transaction_names,
      :transaction_sources,
      :contexts,
      :extra,
      :tags,
      :user,
      :level,
      :breadcrumbs,
      :fingerprint,
      :event_processors,
      :rack_env,
      :span,
      :session
    ]

    attr_reader(*ATTRIBUTES)

    # @param max_breadcrumbs [Integer] the maximum number of breadcrumbs to be stored in the scope.
    def initialize(max_breadcrumbs: nil)
      @max_breadcrumbs = max_breadcrumbs
      set_default_value
    end

    # Resets the scope's attributes to defaults.
    # @return [void]
    def clear
      set_default_value
    end

    # Applies stored attributes and event processors to the given event.
    # @param event [Event]
    # @param hint [Hash] the hint data that'll be passed to event processors.
    # @return [Event]
    def apply_to_event(event, hint = nil)
      event.tags = tags.merge(event.tags)
      event.user = user.merge(event.user)
      event.extra = extra.merge(event.extra)
      event.contexts = contexts.merge(event.contexts)
      event.transaction = transaction_name if transaction_name
      event.transaction_info = { source: transaction_source } if transaction_source

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

    # Adds the breadcrumb to the scope's breadcrumbs buffer.
    # @param breadcrumb [Breadcrumb]
    # @return [void]
    def add_breadcrumb(breadcrumb)
      breadcrumbs.record(breadcrumb)
    end

    # Clears the scope's breadcrumbs buffer
    # @return [void]
    def clear_breadcrumbs
      set_new_breadcrumb_buffer
    end

    # @return [Scope]
    def dup
      copy = super
      copy.breadcrumbs = breadcrumbs.dup
      copy.contexts = contexts.deep_dup
      copy.extra = extra.deep_dup
      copy.tags = tags.deep_dup
      copy.user = user.deep_dup
      copy.transaction_names = transaction_names.dup
      copy.transaction_sources = transaction_sources.dup
      copy.fingerprint = fingerprint.deep_dup
      copy.span = span.deep_dup
      copy.session = session.deep_dup
      copy
    end

    # Updates the scope's data from a given scope.
    # @param scope [Scope]
    # @return [void]
    def update_from_scope(scope)
      self.breadcrumbs = scope.breadcrumbs
      self.contexts = scope.contexts
      self.extra = scope.extra
      self.tags = scope.tags
      self.user = scope.user
      self.transaction_names = scope.transaction_names
      self.transaction_sources = scope.transaction_sources
      self.fingerprint = scope.fingerprint
      self.span = scope.span
    end

    # Updates the scope's data from the given options.
    # @param contexts [Hash]
    # @param extras [Hash]
    # @param tags [Hash]
    # @param user [Hash]
    # @param level [String, Symbol]
    # @param fingerprint [Array]
    # @return [void]
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

    # Sets the scope's rack_env attribute.
    # @param env [Hash]
    # @return [Hash]
    def set_rack_env(env)
      env = env || {}
      @rack_env = env
    end

    # Sets the scope's span attribute.
    # @param span [Span]
    # @return [Span]
    def set_span(span)
      check_argument_type!(span, Span)
      @span = span
    end

    # @!macro set_user
    def set_user(user_hash)
      check_argument_type!(user_hash, Hash)
      @user = user_hash
    end

    # @!macro set_extras
    def set_extras(extras_hash)
      check_argument_type!(extras_hash, Hash)
      @extra.merge!(extras_hash)
    end

    # Adds a new key-value pair to current extras.
    # @param key [String, Symbol]
    # @param value [Object]
    # @return [Hash]
    def set_extra(key, value)
      set_extras(key => value)
    end

    # @!macro set_tags
    def set_tags(tags_hash)
      check_argument_type!(tags_hash, Hash)
      @tags.merge!(tags_hash)
    end

    # Adds a new key-value pair to current tags.
    # @param key [String, Symbol]
    # @param value [Object]
    # @return [Hash]
    def set_tag(key, value)
      set_tags(key => value)
    end

    # Updates the scope's contexts attribute by merging with the old value.
    # @param contexts [Hash]
    # @return [Hash]
    def set_contexts(contexts_hash)
      check_argument_type!(contexts_hash, Hash)
      @contexts.merge!(contexts_hash) do |key, old, new|
        old.merge(new)
      end
    end

    # @!macro set_context
    def set_context(key, value)
      check_argument_type!(value, Hash)
      set_contexts(key => value)
    end

    # Sets the scope's level attribute.
    # @param level [String, Symbol]
    # @return [void]
    def set_level(level)
      @level = level
    end

    # Appends a new transaction name to the scope.
    # The "transaction" here does not refer to `Transaction` objects.
    # @param transaction_name [String]
    # @return [void]
    def set_transaction_name(transaction_name, source: :custom)
      @transaction_names << transaction_name
      @transaction_sources << source
    end

    # Sets the currently active session on the scope.
    # @param session [Session, nil]
    # @return [void]
    def set_session(session)
      @session = session
    end

    # Returns current transaction name.
    # The "transaction" here does not refer to `Transaction` objects.
    # @return [String, nil]
    def transaction_name
      @transaction_names.last
    end

    # Returns current transaction source.
    # The "transaction" here does not refer to `Transaction` objects.
    # @return [String, nil]
    def transaction_source
      @transaction_sources.last
    end

    # Returns the associated Transaction object.
    # @return [Transaction, nil]
    def get_transaction
      span.transaction if span
    end

    # Returns the associated Span object.
    # @return [Span, nil]
    def get_span
      span
    end

    # Sets the scope's fingerprint attribute.
    # @param fingerprint [Array]
    # @return [Array]
    def set_fingerprint(fingerprint)
      check_argument_type!(fingerprint, Array)

      @fingerprint = fingerprint
    end

    # Adds a new event processor [Proc] to the scope.
    # @param block [Proc]
    # @return [void]
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
      @transaction_sources = []
      @event_processors = []
      @rack_env = {}
      @span = nil
      @session = nil
      set_new_breadcrumb_buffer
    end

    def set_new_breadcrumb_buffer
      @breadcrumbs = BreadcrumbBuffer.new(@max_breadcrumbs)
    end

    class << self
      # @return [Hash]
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

      # @return [Hash]
      def runtime_context
        @runtime_context ||= {
          name: RbConfig::CONFIG["ruby_install_name"],
          version: RUBY_DESCRIPTION || Sentry.sys_command("ruby -v")
        }
      end
    end

  end
end
