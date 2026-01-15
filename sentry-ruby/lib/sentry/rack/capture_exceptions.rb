# frozen_string_literal: true

module Sentry
  module Rack
    class CaptureExceptions
      ERROR_EVENT_ID_KEY = "sentry.error_event_id"
      MECHANISM_TYPE = "rack"
      SPAN_ORIGIN = "auto.http.rack"

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Sentry.initialized?

        # make sure the current thread has a clean hub
        Sentry.clone_hub_to_current_thread

        Sentry.with_scope do |scope|
          Sentry.with_session_tracking do
            scope.clear_breadcrumbs
            scope.set_transaction_name(env["PATH_INFO"], source: :url) if env["PATH_INFO"]
            scope.set_rack_env(env)

            transaction = start_transaction(env, scope)
            scope.set_span(transaction) if transaction

            begin
              response = @app.call(env)
            rescue Sentry::Error
              finish_transaction(transaction, 500)
              raise # Don't capture Sentry errors
            rescue Exception => e
              capture_exception(e, env)
              finish_transaction(transaction, 500)
              raise
            end

            exception = collect_exception(env)
            capture_exception(exception, env) if exception

            finish_transaction(transaction, response[0])

            response
          end
        end
      end

      private

      def collect_exception(env)
        env["rack.exception"] || env["sinatra.error"]
      end

      def transaction_op
        "http.server"
      end

      def capture_exception(exception, env)
        Sentry.capture_exception(exception, hint: { mechanism: mechanism }).tap do |event|
          env[ERROR_EVENT_ID_KEY] = event.event_id if event
        end
      end

      def start_transaction(env, scope)
        options = {
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: transaction_op,
          origin: SPAN_ORIGIN
        }

        transaction = Sentry.continue_trace(env, **options)
        transaction = Sentry.start_transaction(transaction: transaction, custom_sampling_context: { env: env }, **options)

        # attach queue time if available
        if transaction && (queue_time = extract_queue_time(env))
          transaction.set_data(Span::DataConventions::HTTP_QUEUE_TIME_MS, queue_time)
        end

        transaction
      end


      def finish_transaction(transaction, status_code)
        return unless transaction

        transaction.set_http_status(status_code)
        transaction.finish
      end

      def mechanism
        Sentry::Mechanism.new(type: MECHANISM_TYPE, handled: false)
      end

      # Extracts queue time from the request environment.
      # Calculates the time (in milliseconds) the request spent waiting in the
      # web server queue before processing began.
      #
      # Subtracts puma.request_body_wait to account for time spent waiting for
      # slow clients to send the request body, isolating actual queue time.
      # See: https://github.com/puma/puma/blob/master/docs/architecture.md
      #
      # @param env [Hash] Rack env
      # @return [Float, nil] queue time in milliseconds or nil
      def extract_queue_time(env)
        return nil unless Sentry.configuration&.capture_queue_time

        header_value = env["HTTP_X_REQUEST_START"]
        return nil unless header_value

        request_start = parse_request_start_header(header_value)
        return nil unless request_start

        total_time_ms = ((Time.now.to_f - request_start) * 1000).round(2)

        # reject negative (clock skew between proxy & app server)
        return nil unless total_time_ms >= 0

        puma_wait_ms = env["puma.request_body_wait"]

        if puma_wait_ms && puma_wait_ms > 0
          queue_time_ms = total_time_ms - puma_wait_ms
          queue_time_ms >= 0 ? queue_time_ms : 0.0 # more sanity check
        else
          total_time_ms
        end
      rescue StandardError
        nil
      end

      # Parses X-Request-Start header value to extract a timestamp.
      # Supports multiple formats:
      #   - Nginx: "t=1234567890.123" (seconds with decimal)
      #   - Heroku, HAProxy 1.9+: "t=1234567890123456" (microseconds)
      #   - HAProxy < 1.9: "t=1234567890" (seconds)
      #   - Generic: "1234567890.123" (raw timestamp)
      #
      # @param header_value [String] The X-Request-Start header value
      # @return [Float, nil] Timestamp in seconds since epoch or nil
      def parse_request_start_header(header_value)
        return nil unless header_value

        timestamp = if header_value.start_with?("t=")
          header_value[2..-1].to_f
        elsif header_value.match?(/\A\d+(?:\.\d+)?\z/)
          header_value.to_f
        else
          return nil
        end

        # normalize: timestamps can be in seconds, milliseconds or microseconds
        # any timestamp > 10 trillion = microseconds
        if timestamp > 10_000_000_000_000
          timestamp / 1_000_000.0
        # timestamp > 10 billion & < 10 trillion = milliseconds
        elsif timestamp > 10_000_000_000
          timestamp / 1_000.0
        else
          timestamp # assume seconds
        end
      rescue StandardError
        nil
      end
    end
  end
end
