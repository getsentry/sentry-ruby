# frozen_string_literal: true

module Sentry
  # Stores the SDK's current {Hub} in an execution-context-local slot.
  #
  # The isolation level decides which execution primitive owns the hub:
  #
  # [+:thread+ (default)] The hub lives in thread-local storage
  #   (+Thread#thread_variable_get+/+thread_variable_set+). This is the SDK's
  #   historical behaviour and is correct for thread-based servers (Puma,
  #   Unicorn) and background processors (Sidekiq, Resque). Every fiber running
  #   on a thread shares one hub.
  #
  # [+:fiber+] The hub lives in Fiber Storage (+Fiber#[]+, Ruby 3.2+). Each
  #   fiber gets its own hub, and a newly created fiber inherits a copy of its
  #   parent's storage, so context still propagates into child fibers (for
  #   example graphql-ruby resolvers or +Async+ tasks) instead of being lost.
  #   This is the correct level for fiber-based servers such as Falcon, where
  #   many concurrent requests run as sibling fibers on a single thread and must
  #   not share a hub.
  #
  # Both levels use the same storage key (+Sentry::THREAD_LOCAL+, value
  # +:sentry_hub+), kept stable for backwards compatibility because integrations
  # and user code reference it directly.
  #
  # @api private
  module HubStorage
    # Isolation levels the SDK understands.
    LEVELS = %i[thread fiber].freeze

    class << self
      # @return [Symbol] the currently active isolation level.
      attr_reader :isolation_level

      # @param level [Symbol] +:thread+ or +:fiber+.
      # @raise [ArgumentError] if +level+ is not a known isolation level.
      # @return [Symbol] the level that was applied.
      def isolation_level=(level)
        @isolation_level = normalize_isolation_level(level)
      end

      # Validates a requested isolation level and downgrades +:fiber+ to
      # +:thread+ when Fiber Storage is unavailable (Ruby < 3.2), so the storage
      # boundary can never be asked to call +Fiber[]+ on a Ruby that lacks it.
      #
      # @param level [Symbol]
      # @raise [ArgumentError] if +level+ is not a known isolation level.
      # @return [Symbol] the level that is safe to apply.
      def normalize_isolation_level(level)
        unless LEVELS.include?(level)
          raise ArgumentError, "isolation_level must be one of #{LEVELS.inspect}, got #{level.inspect}"
        end

        level == :fiber && !fiber_storage_available? ? :thread : level
      end

      # @return [Hub, nil] the hub stored for the current execution context.
      def get
        if @isolation_level == :fiber
          ::Fiber[THREAD_LOCAL]
        else
          ::Thread.current.thread_variable_get(THREAD_LOCAL)
        end
      end

      # @param hub [Hub, nil]
      # @return [Hub, nil]
      def set(hub)
        if @isolation_level == :fiber
          ::Fiber[THREAD_LOCAL] = hub
        else
          ::Thread.current.thread_variable_set(THREAD_LOCAL, hub)
        end
      end

      # Clears the hub for the current execution context.
      # @return [void]
      def clear
        set(nil)
      end

      # Whether the running Ruby exposes Fiber Storage (+Fiber#[]+, Ruby 3.2+),
      # the primitive the +:fiber+ isolation level is built on.
      # @return [Boolean]
      def fiber_storage_available?
        ::Fiber.respond_to?(:[]) && ::Fiber.respond_to?(:[]=)
      end
    end

    self.isolation_level = :thread
  end
end
