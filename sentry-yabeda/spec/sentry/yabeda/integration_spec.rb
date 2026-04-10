# frozen_string_literal: true

require "spec_helper"

# Integration test exercising real Yabeda metrics flowing through to Sentry.
# Yabeda's global state (singleton methods, metrics registry) can only be
# configured once per process, so we define all metrics up front and run
# assertions against them.

::Yabeda.configure do
  group :myapp do
    counter   :orders_created, comment: "Orders placed",      tags: %i[region payment_method]
    gauge     :queue_depth,    comment: "Jobs waiting",       tags: %i[queue_name]
    histogram :response_time,  comment: "HTTP response time", unit: :milliseconds, tags: %i[controller action],
              buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
  end

  counter :global_requests, comment: "Total requests (no group)"
end

::Yabeda.configure! unless ::Yabeda.configured?

RSpec.describe "Yabeda-Sentry integration" do
  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
      config.release = "test-release"
      config.environment = "test"
    end
  end

  it "forwards counter increments to Sentry" do
    ::Yabeda.myapp.orders_created.increment({ region: "us-east", payment_method: "credit_card" })

    Sentry.get_current_client.flush

    expect(sentry_metrics.count).to eq(1)

    metric = sentry_metrics.first
    expect(metric[:name]).to eq("myapp.orders_created")
    expect(metric[:type]).to eq(:counter)
    expect(metric[:value]).to eq(1)
    expect(metric[:attributes][:region]).to eq({ type: "string", value: "us-east" })
    expect(metric[:attributes][:payment_method]).to eq({ type: "string", value: "credit_card" })
  end

  it "forwards counter increments with custom value" do
    ::Yabeda.myapp.orders_created.increment({ region: "eu-west" }, by: 5)

    Sentry.get_current_client.flush

    metric = sentry_metrics.first
    expect(metric[:value]).to eq(5)
  end

  it "forwards gauge sets to Sentry" do
    ::Yabeda.myapp.queue_depth.set({ queue_name: "default" }, 42)

    Sentry.get_current_client.flush

    expect(sentry_metrics.count).to eq(1)

    metric = sentry_metrics.first
    expect(metric[:name]).to eq("myapp.queue_depth")
    expect(metric[:type]).to eq(:gauge)
    expect(metric[:value]).to eq(42)
    expect(metric[:attributes][:queue_name]).to eq({ type: "string", value: "default" })
  end

  it "forwards histogram observations to Sentry as distributions" do
    ::Yabeda.myapp.response_time.measure({ controller: "orders", action: "index" }, 150.5)

    Sentry.get_current_client.flush

    expect(sentry_metrics.count).to eq(1)

    metric = sentry_metrics.first
    expect(metric[:name]).to eq("myapp.response_time")
    expect(metric[:type]).to eq(:distribution)
    expect(metric[:value]).to eq(150.5)
    expect(metric[:unit]).to eq("milliseconds")
    expect(metric[:attributes][:controller]).to eq({ type: "string", value: "orders" })
    expect(metric[:attributes][:action]).to eq({ type: "string", value: "index" })
  end

  it "handles metrics without a group" do
    ::Yabeda.global_requests.increment({})

    Sentry.get_current_client.flush

    metric = sentry_metrics.first
    expect(metric[:name]).to eq("global_requests")
    expect(metric[:type]).to eq(:counter)
  end

  it "batches multiple Yabeda metrics into a single Sentry envelope" do
    ::Yabeda.myapp.orders_created.increment({ region: "us-east" })
    ::Yabeda.myapp.queue_depth.set({ queue_name: "default" }, 10)
    ::Yabeda.myapp.response_time.measure({ controller: "home", action: "index" }, 50.0)

    Sentry.get_current_client.flush

    expect(sentry_envelopes.count).to eq(1)
    expect(sentry_metrics.count).to eq(3)

    metric_names = sentry_metrics.map { |m| m[:name] }
    expect(metric_names).to contain_exactly(
      "myapp.orders_created",
      "myapp.queue_depth",
      "myapp.response_time"
    )
  end

  it "carries trace context on metrics" do
    transaction = Sentry.start_transaction(name: "test_transaction", op: "test.op")
    Sentry.get_current_scope.set_span(transaction)

    ::Yabeda.myapp.orders_created.increment({ region: "us-east" })

    transaction.finish
    Sentry.get_current_client.flush

    metric = sentry_metrics.first
    expect(metric[:trace_id]).to eq(transaction.trace_id)
  end

  context "when metrics are disabled" do
    before do
      Sentry.configuration.enable_metrics = false
    end

    it "does not send metrics to Sentry" do
      ::Yabeda.myapp.orders_created.increment({ region: "us-east" })

      Sentry.get_current_client.flush

      expect(sentry_metrics).to be_empty
    end
  end
end

RSpec.describe "Yabeda-Sentry integration when Sentry is not initialized" do
  it "does not raise errors when Yabeda metrics are emitted" do
    # Sentry is not initialized (reset_sentry_globals! runs after each test)
    expect { ::Yabeda.myapp.orders_created.increment({ region: "us-east" }) }.not_to raise_error
  end
end
