# frozen_string_literal: true

module Sentry
  module TestHelper
    module_function

    DUMMY_DSN = "http://12345:67890@sentry.localdomain/sentry/42"

    # Not really real, but it will be resolved as a non-local for testing needs
    REAL_DSN = "https://user:pass@getsentry.io/project/42"

    # Alters the existing SDK configuration with test-suitable options. Mainly:
    # - Sets a dummy DSN instead of `nil` or an actual DSN.
    # - Sets the transport to DummyTransport, which allows easy access to the captured events.
    # - Disables background worker.
    # - Makes sure the SDK is enabled under the current environment ("test" in most cases).
    #
    # It should be called **before** every test case.
    #
    # @yieldparam config [Configuration]
    # @return [void]
    def setup_sentry_test(&block)
      raise "please make sure the SDK is initialized for testing" unless Sentry.initialized?
      dummy_config = Sentry.configuration.dup
      # configure dummy DSN, so the events will not be sent to the actual service
      dummy_config.dsn = DUMMY_DSN
      # set transport to DummyTransport, so we can easily intercept the captured events
      dummy_config.transport.transport_class = Sentry::DummyTransport
      # make sure SDK allows sending under the current environment
      dummy_config.enabled_environments ||= []
      dummy_config.enabled_environments += [dummy_config.environment] unless dummy_config.enabled_environments.include?(dummy_config.environment)
      # disble async event sending
      dummy_config.background_worker_threads = 0

      # user can overwrite some of the configs, with a few exceptions like:
      # - include_local_variables
      # - auto_session_tracking
      block&.call(dummy_config)

      # Install the testing clients on the *main* hub rather than the current
      # thread's hub. `Sentry.clone_hub_to_current_thread` (used by
      # Sentry::Rack::CaptureExceptions) always clones the main hub, so if we
      # only mutated the thread-local hub a request-time clone would observe a
      # stale transport.
      main_hub = Sentry.get_main_hub

      # the base layer's client should already use the dummy config so nothing will be sent by accident
      base_client = Sentry::Client.new(dummy_config)
      main_hub.bind_client(base_client)
      # create a new layer so mutations made to the testing scope or configuration could be simply popped later
      main_hub.push_scope
      test_client = Sentry::Client.new(dummy_config.dup)
      main_hub.bind_client(test_client)

      # Realign the current thread's hub with the main hub so direct
      # `sentry_events` reads and any hub the Rack middleware clones from the
      # main hub all observe the same DummyTransport.
      Thread.current.thread_variable_set(Sentry::THREAD_LOCAL, main_hub)
    end

    # Clears all stored events and envelopes.
    # It should be called **after** every test case.
    # @return [void]
    def teardown_sentry_test
      return unless Sentry.initialized?

      clear_sentry_events

      # pop the testing layer created by `setup_sentry_test` off the *main*
      # hub (that is where `setup_sentry_test` pushed it), keeping the base
      # layer to avoid nil-pointer errors. Popping the current thread's hub
      # would leave the test layer dangling on the main hub, which the next
      # request-time clone would inherit.
      # TODO: find a way to notify users if they somehow popped the test layer before calling this method
      main_hub = Sentry.get_main_hub
      if main_hub.instance_variable_get(:@stack).size > 1
        main_hub.pop_scope
      end
      Sentry::Scope.global_event_processors.clear
    end

    def clear_sentry_events
      return unless Sentry.initialized?

      # Clear every transport reachable from the current thread's hub and the
      # main hub (including its base layer). A request-time clone shares the
      # main hub's base-layer transport, so clearing only the current
      # transport would let stale events survive into the next test.
      sentry_test_transports.each do |transport|
        transport.clear if transport.respond_to?(:clear)
      end

      if Sentry.configuration.enable_logs && sentry_logger.respond_to?(:clear)
        sentry_logger.clear
      end
    end

    # @return [Sentry::StructuredLogger, Sentry::DebugStructuredLogger]
    def sentry_logger
      Sentry.logger
    end

    # @return [Transport]
    def sentry_transport
      Sentry.get_current_client.transport
    end

    # Every transport reachable from the current thread's hub and the main
    # hub, across all stack layers. Used by `clear_sentry_events` so a stale
    # DummyTransport (e.g. the main hub's base layer that a request-time clone
    # shares) cannot carry leftover events into the next test.
    # @return [Array<Transport>]
    def sentry_test_transports
      [Sentry.get_current_hub, Sentry.get_main_hub].compact.uniq.flat_map do |hub|
        hub.clients.map(&:transport)
      end.compact.uniq
    end

    # Returns the captured event objects.
    # @return [Array<Event>]
    def sentry_events
      sentry_transport.events
    end

    # Returns the captured envelope objects.
    # @return [Array<Envelope>]
    def sentry_envelopes
      sentry_transport.envelopes
    end

    def sentry_logs
      sentry_envelopes
        .flat_map(&:items)
        .select { |item| item.headers[:type] == "log" }
        .flat_map { |item| item.payload[:items] }
    end

    def sentry_metrics
      sentry_envelopes
        .flat_map(&:items)
        .select { |item| item.headers[:type] == "trace_metric" }
        .flat_map { |item| item.payload[:items] }
    end

    # Returns the last captured event object.
    # @return [Event, nil]
    def last_sentry_event
      sentry_events.last
    end

    # Extracts SDK's internal exception container (not actual exception objects) from an given event.
    # @return [Array<Sentry::SingleExceptionInterface>]
    def extract_sentry_exceptions(event)
      event&.exception&.values || []
    end

    def reset_sentry_globals!
      Sentry::MUTEX.synchronize do
        # Don't check initialized? because sometimes we stub it in tests
        if Sentry.instance_variable_defined?(:@main_hub)
          Sentry::GLOBALS.each do |var|
            worker = Sentry.instance_variable_get(:"@#{var}")
            worker.kill if worker.respond_to?(:kill)

            Sentry.instance_variable_set(:"@#{var}", nil)
          end

          Thread.current.thread_variable_set(Sentry::THREAD_LOCAL, nil)
        end
      end
    end
  end
end
