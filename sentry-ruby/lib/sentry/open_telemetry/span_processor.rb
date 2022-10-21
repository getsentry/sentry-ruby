module Sentry
  module OpenTelemetry
    class SpanProcessor

      ATTRIBUTE_NET_PEER_NAME = "net.peer.name"
      ATTRIBUTE_DB_STATEMENT = "db.statement"

      def initialize
        @otel_span_map = {}
      end

      def on_start(otel_span, _parent_context)
        return unless Sentry.initialized? && Sentry.configuration.instrumenter == :otel
        return if from_sentry_sdk?(otel_span)

        scope = Sentry.get_current_scope
        parent_sentry_span = scope.get_span

        sentry_span = if parent_sentry_span
          Sentry.configuration.logger.info("Continuing otel span #{otel_span.name} on parent #{parent_sentry_span.name}")
          parent_sentry_span.start_child(description: otel_span.name)
        else
          options = { name: otel_span.name }
          sentry_trace = scope.sentry_trace
          baggage = scope.baggage
          transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, baggage: baggage, **options) if sentry_trace
          Sentry.configuration.logger.info("Starting otel transaction #{otel_span.name}")
          Sentry.start_transaction(transaction: transaction, instrumenter: :otel, **options)
        end

        scope.set_span(sentry_span)
        @otel_span_map[otel_span.context.span_id] = [sentry_span, parent_sentry_span]
      end

      def on_finish(otel_span)
        return unless Sentry.initialized? && Sentry.configuration.instrumenter == :otel

        current_scope = Sentry.get_current_scope
        sentry_span, parent_span = @otel_span_map.delete(otel_span.context.span_id)
        return unless sentry_span

        # TODO-neel ops
        sentry_span.set_op(otel_span.name)

        if sentry_span.is_a?(Sentry::Transaction)
          current_scope.set_transaction_name(otel_span.name)
          current_scope.set_context(:otel, otel_context_hash(otel_span))
        else
          otel_span.attributes&.each do |key, value|
            sentry_span.set_data(key, value)
            if key == ATTRIBUTE_DB_STATEMENT
              sentry_span.set_description(value)
            end
          end
        end

        Sentry.configuration.logger.info("Finishing sentry_span #{sentry_span.op}")
        sentry_span.finish
        current_scope.set_span(parent_span) if parent_span
      end

      def force_flush(timeout: nil)
        # no-op: we rely on Sentry.close being called for the same reason as
        # whatever triggered this shutdown.
      end

      def shutdown(timeout: nil)
        # no-op: we rely on Sentry.close being called for the same reason as
        # whatever triggered this shutdown.
      end

      private

      def from_sentry_sdk?(otel_span)
        dsn = Sentry.configuration.dsn
        return false unless dsn

        if otel_span.name.start_with?("HTTP")
          # only check client requests, connects are sometimes internal
          return false unless %i(client internal).include?(otel_span.kind)

          address = otel_span.attributes[ATTRIBUTE_NET_PEER_NAME]

          # if no address drop it, just noise
          return true unless address
          return true if dsn.host == address
        end

        false
      end

      def otel_context_hash(otel_span)
        otel_context = {}
        otel_context[:attributes] = otel_span.attributes unless otel_span.attributes.empty?

        resource_attributes = otel_span.resource.attribute_enumerator.to_h

        service = {}
        service[:name] = resource_attributes.delete("service.name")
        service[:namespace] = resource_attributes.delete("service.namespace")
        service[:instance_id] = resource_attributes.delete("service.instance.id")
        service[:version] = resource_attributes.delete("service.version")
        service.compact!

        otel_context[:service] = service unless service.empty?

        otel_sdk = {}
        otel_sdk[:name] = resource_attributes.delete("telemetry.sdk.name")
        otel_sdk[:language] = resource_attributes.delete("telemetry.sdk.language")
        otel_sdk[:version] = resource_attributes.delete("telemetry.sdk.version")
        otel_sdk[:auto_version] = resource_attributes.delete("telemetry.auto.version")
        otel_sdk.compact!

        otel_context[:otel_sdk] = otel_sdk unless otel_sdk.empty?

        # remaining resource_attributes just go to the main hash
        otel_context.merge!(resource_attributes)
      end
    end
  end
end
