# frozen_string_literal: true

RSpec.describe "Sentry Metrics" do
  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
      config.release = "test-release"
      config.environment = "test"
      config.server_name = "my-server"
    end
  end

  describe "Sentry.metrics" do
    context "when metrics are disabled" do
      before do
        Sentry.configuration.enable_metrics = false
      end

      it "doesn't send metrics" do
        Sentry.metrics.count("test.counter")
        Sentry.metrics.gauge("test.gauge", 42.5, unit: "seconds")
        Sentry.metrics.distribution("test.gauge", 42.5, attributes: { foo: "bar" })
        Sentry.get_current_client.flush

        expect(sentry_metrics).to be_empty
      end
    end

    context "when metrics are enabled" do
      describe ".count" do
        it "sends a counter metric with default value" do
          Sentry.metrics.count("test.counter")

          Sentry.get_current_client.flush

          expect(sentry_envelopes.count).to eq(1)
          expect(sentry_metrics.count).to eq(1)

          metric = sentry_metrics.first
          expect(metric[:name]).to eq("test.counter")
          expect(metric[:type]).to eq(:counter)
          expect(metric[:value]).to eq(1)
        end

        it "sends a counter metric with custom value" do
          Sentry.metrics.count("test.counter", value: 5)

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          expect(metric[:name]).to eq("test.counter")
          expect(metric[:type]).to eq(:counter)
          expect(metric[:value]).to eq(5)
        end

        it "includes custom attributes" do
          Sentry.metrics.count("test.counter", attributes: { "foo" => "bar", "count" => 42 })

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          attributes = metric[:attributes]

          expect(attributes["foo"]).to eq({ type: "string", value: "bar" })
          expect(attributes["count"]).to eq({ type: "integer", value: 42 })
        end
      end

      describe ".gauge" do
        it "sends a gauge metric" do
          Sentry.metrics.gauge("test.gauge", 42.5)

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          expect(metric[:name]).to eq("test.gauge")
          expect(metric[:type]).to eq(:gauge)
          expect(metric[:value]).to eq(42.5)
        end

        it "includes custom unit" do
          Sentry.metrics.gauge("test.memory", 1024, unit: "bytes")

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          expect(metric[:unit]).to eq("bytes")
        end

        it "includes custom attributes" do
          Sentry.metrics.gauge("test.gauge", 100, attributes: { "region" => "us-west" })

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          attributes = metric[:attributes]

          expect(attributes["region"]).to eq({ type: "string", value: "us-west" })
        end
      end

      describe ".distribution" do
        it "sends a distribution metric" do
          Sentry.metrics.distribution("test.distribution", 3.14)

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          expect(metric[:name]).to eq("test.distribution")
          expect(metric[:type]).to eq(:distribution)
          expect(metric[:value]).to eq(3.14)
        end

        it "includes custom unit" do
          Sentry.metrics.distribution("test.duration", 1.5, unit: "seconds")

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          expect(metric[:unit]).to eq("seconds")
        end

        it "includes custom attributes" do
          Sentry.metrics.distribution("test.latency", 250, unit: "milliseconds", attributes: { "endpoint" => "/api/users" })

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          attributes = metric[:attributes]

          expect(attributes["endpoint"]).to eq({ type: "string", value: "/api/users" })
        end
      end

      it "includes trace_id from the scope's propagation context when no span is set" do
        Sentry.metrics.count("test.counter")

        Sentry.get_current_client.flush

        propagation_context = Sentry.get_current_scope.propagation_context

        metric = sentry_metrics.first
        expect(metric[:trace_id]).to eq(propagation_context.trace_id)
        expect(metric[:span_id]).to eq(propagation_context.span_id)
      end

      context "with active transaction" do
        it "includes trace_id and span_id from the active span" do
          transaction = Sentry.start_transaction(name: "test_transaction", op: "test.op")
          span = transaction.start_child(op: "child span")

          Sentry.get_current_scope.set_span(span)

          Sentry.metrics.count("test.counter")

          transaction.finish

          Sentry.get_current_client.flush

          # 2 envelopes: metric and transaction
          expect(sentry_envelopes.size).to eq(2)

          metric = sentry_metrics.first

          expect(metric[:trace_id]).to eq(span.trace_id)
          expect(metric[:span_id]).to eq(span.span_id)
        end
      end

      context "with user data on scope" do
        before do
          Sentry.configure_scope do |scope|
            scope.set_user({ id: 123, username: "jane", email: "jane@example.com" })
          end
        end

        context "when send_default_pii is true" do
          before do
            Sentry.configuration.send_default_pii = true
          end

          it "includes user attributes in the metric" do
            Sentry.metrics.count("test.counter")

            Sentry.get_current_client.flush

            metric = sentry_metrics.first
            attributes = metric[:attributes]

            expect(attributes["user.id"]).to eq({ type: "integer", value: 123 })
            expect(attributes["user.name"]).to eq({ type: "string", value: "jane" })
            expect(attributes["user.email"]).to eq({ type: "string", value: "jane@example.com" })
          end
        end

        context "when send_default_pii is false" do
          it "does not include user attributes" do
            Sentry.metrics.count("test.counter")

            Sentry.get_current_client.flush

            metric = sentry_metrics.first
            attributes = metric[:attributes]

            expect(attributes).not_to have_key("user.id")
            expect(attributes).not_to have_key("user.name")
            expect(attributes).not_to have_key("user.email")
          end
        end
      end

      it "includes default attributes from configuration" do
        Sentry.metrics.count("test.counter")

        Sentry.get_current_client.flush

        metric = sentry_metrics.first
        attributes = metric[:attributes]

        expect(attributes["sentry.environment"]).to eq({ type: "string", value: "test" })
        expect(attributes["sentry.release"]).to eq({ type: "string", value: "test-release" })
        expect(attributes["server.address"]).to eq({ type: "string", value: "my-server" })
        expect(attributes["sentry.sdk.name"]).to eq({ type: "string", value: Sentry.sdk_meta["name"] })
        expect(attributes["sentry.sdk.version"]).to eq({ type: "string", value: Sentry.sdk_meta["version"] })
      end

      it "batches multiple metrics into a single envelope" do
        Sentry.metrics.count("test.counter1", value: 1)
        Sentry.metrics.count("test.counter2", value: 2)
        Sentry.metrics.gauge("test.gauge", 42)

        Sentry.get_current_client.flush

        expect(sentry_envelopes.count).to eq(1)
        expect(sentry_metrics.count).to eq(3)

        metric_names = sentry_metrics.map { |m| m[:name] }
        expect(metric_names).to contain_exactly("test.counter1", "test.counter2", "test.gauge")
      end

      describe "envelope structure" do
        it "includes correct envelope headers" do
          Sentry.metrics.count("test.counter")
          Sentry.get_current_client.flush

          envelope = sentry_envelopes.first
          headers = envelope.headers

          expect(headers[:event_id]).to match(/\A[0-9a-f]{32}\z/) # UUID format
          expect(headers[:sent_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/) # ISO8601 timestamp
          expect(headers[:dsn]).to eq(Sentry.configuration.dsn)
          expect(headers[:sdk]).to eq(Sentry.sdk_meta)
        end

        it "includes correct envelope item headers" do
          Sentry.metrics.count("test.counter1")
          Sentry.metrics.gauge("test.gauge", 42)
          Sentry.get_current_client.flush

          envelope = sentry_envelopes.first
          item = envelope.items.first

          # Verify envelope item headers
          expect(item.headers[:type]).to eq("trace_metric")
          expect(item.headers[:item_count]).to eq(2)
          expect(item.headers[:content_type]).to eq("application/vnd.sentry.items.trace-metric+json")
        end

        it "includes correct payload structure" do
          Sentry.metrics.count("test.counter")
          Sentry.get_current_client.flush

          envelope = sentry_envelopes.first
          item = envelope.items.first
          payload = item.payload

          # Verify payload structure
          expect(payload).to have_key(:items)
          expect(payload[:items]).to be_an(Array)
          expect(payload[:items].size).to eq(1)

          metric_item = payload[:items].first
          expect(metric_item).to be_a(Hash)
          expect(metric_item).to have_key(:name)
          expect(metric_item).to have_key(:type)
          expect(metric_item).to have_key(:value)
          expect(metric_item).to have_key(:attributes)
          expect(metric_item).to have_key(:trace_id)
          expect(metric_item).to have_key(:span_id)
        end
      end

      context "with before_send_metric callback" do
        it "receives MetricEvent" do
          perform_basic_setup do |config|
            config.before_send_metric = lambda do |metric|
              expect(metric).to be_a(Sentry::MetricEvent)
              metric
            end
          end

          Sentry.metrics.gauge("test.gauge", 42.5, unit: "seconds", attributes: { "foo" => "bar" })
          Sentry.get_current_client.flush
        end

        it "allows modifying metrics before sending" do
          perform_basic_setup do |config|
            config.before_send_metric = lambda do |metric|
              metric.attributes["modified"] = true
              metric
            end
          end

          Sentry.metrics.count("test.counter")

          Sentry.get_current_client.flush

          metric = sentry_metrics.first
          expect(metric[:attributes]["modified"]).to eq({ type: "boolean", value: true })
        end

        it "filters out metrics when callback returns nil" do
          perform_basic_setup do |config|
            config.before_send_metric = lambda do |metric|
              metric.name == "test.filtered" ? nil : metric
            end
          end

          Sentry.metrics.count("test.filtered")
          Sentry.metrics.gauge("test.filtered", 42)
          Sentry.metrics.count("test.allowed")

          Sentry.get_current_client.flush

          expect(sentry_metrics.count).to eq(1)
          expect(sentry_metrics.first[:name]).to eq("test.allowed")
          expect(Sentry.get_current_client.transport).to have_recorded_lost_event(:before_send, 'trace_metric', num: 2)
        end
      end
    end
  end
end
