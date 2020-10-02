require "sentry/scope"
require "sentry/client"

module Sentry
  class Hub
    attr_reader :client, :scopes, :last_event_id

    def initialize(client, scope)
      @client = client
      @scopes = [scope]
      @last_event_id = nil
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

      @scopes.push(new_scope)
    end

    def pop_scope
      @scopes.pop
    end

    def capture_exception(error, **options, &block)
      event = @client.event_from_exception(error, **options)

      return unless current_scope

      current_scope.apply_to_event(event)
      yield(event) if block_given?
      capture_event(event)
    end

    def capture_message(message, **options, &block)
      event = @client.event_from_message(message, **options)

      return unless current_scope

      current_scope.apply_to_event(event)
      yield(event) if block_given?
      capture_event(event)
    end

    def capture_event(event)
      @client.send_event(event)
      @last_event_id = event.id
      event
    end

    def add_breadcrumb(breadcrumb)
      current_scope.add_breadcrumb(breadcrumb)
    end

    def current_scope
      @scopes.last
    end
  end
end
