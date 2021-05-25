module Sentry
  module Lambda
    class CaptureExceptions
      TIMEOUT_WARNING_BUFFER = 1500 # Buffer time required to send timeout warning to Sentry

      def initialize(aws_event:, aws_context:, capture_timeout_warning: false)
        @aws_event = aws_event
        @aws_context = aws_context
        @capture_timeout_warning = capture_timeout_warning
      end

      def call(&block)
        return yield unless Sentry.initialized?

        if @capture_timeout_warning && (@aws_context.get_remaining_time_in_millis > TIMEOUT_WARNING_BUFFER)
          Thread.new do
            configured_timeout_seconds = @aws_context.get_remaining_time_in_millis / 1000.0
            sleep_timeout_seconds = ((@aws_context.get_remaining_time_in_millis - TIMEOUT_WARNING_BUFFER) / 1000.0)

            timeout_message = "WARNING : Function is expected to get timed out. "\
                              "Configured timeout duration = #{configured_timeout_seconds.round} seconds."

            sleep(sleep_timeout_seconds)
            Sentry.capture_message(timeout_message)
          end
        end

        # make sure the current thread has a clean hub
        Sentry.clone_hub_to_current_thread

        Sentry.with_scope do |scope|
          start_time = Time.now.utc
          initial_remaining_time_in_milis = @aws_context.get_remaining_time_in_millis
          execution_expiration_time = Time.now.utc + ((initial_remaining_time_in_milis || 0)/1000.0)

          scope.clear_breadcrumbs
          scope.set_transaction_name(@aws_context.function_name)

          scope.add_event_processor do |event, hint|
            event_time = event.timestamp.is_a?(Float) ? Time.at(event.timestamp) : Time.parse(event.timestamp)
            remaining_time_in_millis = ((execution_expiration_time - event_time) * 1000).round
            execution_duration_in_millis = ((event_time - start_time) * 1000).round
            event.extra = event.extra.merge(
              lambda: {
                function_name: @aws_context.function_name,
                function_version: @aws_context.function_version,
                invoked_function_arn: @aws_context.invoked_function_arn,
                aws_request_id: @aws_context.aws_request_id,
                execution_duration_in_millis: execution_duration_in_millis,
                remaining_time_in_millis: remaining_time_in_millis
              }
            )

            event.extra = event.extra.merge(
              "cloudwatch logs": {
                url: _get_cloudwatch_logs_url(@aws_context, start_time),
                log_group: @aws_context.log_group_name,
                log_stream: @aws_context.log_stream_name
              }
            )

            event
          end

          transaction = start_transaction(@aws_event, @aws_context, scope.transaction_name)
          scope.set_span(transaction) if transaction

          begin
            response = yield
          rescue Sentry::Error
            finish_transaction(transaction, 500)
            raise # Don't capture Sentry errors
          rescue Exception => e
            capture_exception(e)
            finish_transaction(transaction, 500)
            raise
          end

          status_code = response&.dig(:statusCode) || response&.dig('statusCode')
          finish_transaction(transaction, status_code)

          response
        end
      end

      def start_transaction(event, context, transaction_name)
        sentry_trace = event["HTTP_SENTRY_TRACE"]
        options = { name: transaction_name, op: 'serverless.function' }
        transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, **options) if sentry_trace
        Sentry.start_transaction(transaction: transaction, **options)
      end

      def finish_transaction(transaction, status_code)
        return unless transaction

        transaction.set_http_status(status_code)
        transaction.finish
      end

      def capture_exception(exception)
        Sentry.capture_exception(exception)
      end

      def _get_cloudwatch_logs_url(aws_context, start_time)
        formatstring = "%Y-%m-%dT%H:%M:%SZ"
        region = ENV['AWS_REGION']

        "https://console.aws.amazon.com/cloudwatch/home?region=#{region}" \
        "#logEventViewer:group=#{aws_context.log_group_name};stream=#{aws_context.log_stream_name}" \
        ";start=#{start_time.strftime(formatstring)};end=#{(Time.now.utc + 2).strftime(formatstring)}"
      end
    end
  end
end
