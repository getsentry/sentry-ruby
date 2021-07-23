require "sentry/scope"
require "sentry/client"

module Sentry
  class Hub
    include ArgumentCheckingHelper

    attr_reader :last_event_id

    def initialize(client, scope)
      first_layer = Layer.new(client, scope)
      @stack = [first_layer]
      @last_event_id = nil
    end

    def new_from_top
      Hub.new(current_client, current_scope)
    end

    def current_client
      current_layer&.client
    end

    def configuration
      current_client.configuration
    end

    def current_scope
      current_layer&.scope
    end

    def clone
      layer = current_layer

      if layer
        scope = layer.scope&.dup

        Hub.new(layer.client, scope)
      end
    end

    def bind_client(client)
      layer = current_layer

      if layer
        layer.client = client
      end
    end

    def configure_scope(&block)
      block.call(current_scope)
    end

    def with_scope(&block)
      push_scope
      yield(current_scope)
    ensure
      pop_scope
    end

    def push_scope
      new_scope =
        if current_scope
          current_scope.dup
        else
          Scope.new
        end

      @stack << Layer.new(current_client, new_scope)
    end

    def pop_scope
      @stack.pop
    end

    def start_transaction(transaction: nil, custom_sampling_context: {}, **options)
      return unless configuration.tracing_enabled?

      transaction ||= Transaction.new(**options.merge(hub: self))

      sampling_context = {
        transaction_context: transaction.to_hash,
        parent_sampled: transaction.parent_sampled
      }

      sampling_context.merge!(custom_sampling_context)

      transaction.set_initial_sample_decision(sampling_context: sampling_context)
      transaction
    end

    def capture_exception(exception, **options, &block)
      return unless current_client

      check_argument_type!(exception, ::Exception)

      options[:hint] ||= {}
      options[:hint][:exception] = exception
      event = current_client.event_from_exception(exception, options[:hint])

      return unless event

      capture_event(event, **options, &block)
    end

    def capture_message(message, **options, &block)
      return unless current_client

      options[:hint] ||= {}
      options[:hint][:message] = message
      event = current_client.event_from_message(message, options[:hint])
      capture_event(event, **options, &block)
    end

    def capture_event(event, **options, &block)
      return unless current_client

      check_argument_type!(event, Sentry::Event)

      hint = options.delete(:hint) || {}
      scope = current_scope.dup

      if block
        block.call(scope)
      elsif custom_scope = options[:scope]
        scope.update_from_scope(custom_scope)
      elsif !options.empty?
        scope.update_from_options(**options)
      end

      event = current_client.capture_event(event, scope, hint)

      @last_event_id = event&.event_id
      event
    end

    def add_breadcrumb(breadcrumb, hint: {})
      if before_breadcrumb = current_client.configuration.before_breadcrumb
        breadcrumb = before_breadcrumb.call(breadcrumb, hint)
      end

      return unless breadcrumb

      current_scope.add_breadcrumb(breadcrumb)
    end

    # this doesn't do anything to the already initialized background worker
    # but it temporarily disables dispatching events to it
    def with_background_worker_disabled(&block)
      original_background_worker_threads = configuration.background_worker_threads
      configuration.background_worker_threads = 0

      block.call
    ensure
      configuration.background_worker_threads = original_background_worker_threads
    end

    private

    def current_layer
      @stack.last
    end

    class Layer
      attr_accessor :client
      attr_reader :scope

      def initialize(client, scope)
        @client = client
        @scope = scope
      end
    end
  end
end
