# frozen_string_literal: true

RSpec.describe Sentry::Redis do
  let(:redis) { Redis.new(host: REDIS_HOST) }

  context "with tracing enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
      end
    end

    describe "data collection" do
      describe "database query data" do
        it "collects Redis arguments when database query data is enabled" do
        Sentry.configuration.data_collection.database_query_data = true
        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        expect(redis.set("key", "value")).to eq("OK")
        expect(transaction.span_recorder.spans.last.description).to eq("SET key value")
      end

        it "does not collect Redis arguments when database query data is disabled" do
          Sentry.configuration.data_collection.database_query_data = false
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          expect(redis.set("key", "value")).to eq("OK")
          expect(transaction.span_recorder.spans.last.description).to eq("SET key")
        end
      end
    end

    describe "credentials" do
      before do
        Sentry.configuration.data_collection.database_query_data = true
        Sentry.configuration.breadcrumbs_logger = [:redis_logger]
      end

      # The test Redis has no password, so the default user accepts any password.
      [
        ["AUTH", "default", "secret"],
        ["HELLO", "2", "AUTH", "default", "secret"]
      ].each do |command|
        it "does not record #{command.first} arguments" do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          redis.call(*command)

          expect(transaction.span_recorder.spans.last.description).to eq(command.first)
          expect(Sentry.get_current_scope.breadcrumbs.peek.data[:commands]).to eq([{ command: command.first }])
        end
      end

      it "records only the subcommand of commands that are not allowlisted" do
        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        redis.call("CONFIG", "GET", "maxmemory")

        expect(transaction.span_recorder.spans.last.description).to eq("CONFIG GET")
        expect(Sentry.get_current_scope.breadcrumbs.peek.data[:commands]).to eq([{ command: "CONFIG", key: "GET" }])
      end
    end

    context "config.send_default_pii = true" do
      before { Sentry.configuration.send_default_pii = true }

      context "calling Redis SET command" do
        let(:result) { redis.set("key", "value") }

        it "records the Redis call's span with command and key" do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          expect(result).to eq("OK")
          request_span = transaction.span_recorder.spans.last
          expect(request_span.op).to eq("db.redis")
          expect(request_span.origin).to eq("auto.db.redis")
          expect(request_span.start_timestamp).not_to be_nil
          expect(request_span.timestamp).not_to be_nil
          expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
          expect(request_span.description).to eq("SET key value")
          expect(request_span.data).to eq({
            "db.name" => 0,
            "db.system" => "redis",
            "server.address" => REDIS_HOST,
            "server.port" => 6379
          })
        end

        it "removes bad encoding keys and arguments gracefully" do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          # random bytes
          redis.set("key \x1F\xE6", "val \x1F\xE6")

          request_span = transaction.span_recorder.spans.last
          description = request_span.description

          expect(description).to eq("SET")

          expect do
            JSON.generate(description)
          end.not_to raise_error
        end
      end
    end

    context "config.send_default_pii = false" do
      before { Sentry.configuration.send_default_pii = false }

      context "calling Redis SET command" do
        let(:result) { redis.set("key", "value") }

        it "records the Redis call's span with command and key" do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          expect(result).to eq("OK")
          expect(transaction.span_recorder.spans.last.description).to eq("SET key")
        end
      end
    end

    context "calling multiple Redis commands in a MULTI transaction" do
      let(:result) do
        redis.multi do |multi|
          multi.set("key", "value")
          multi.incr("counter")
        end
      end

      it "records the Redis call's span with command and key" do
        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        expect(result).to contain_exactly("OK", kind_of(Numeric))
        request_span = transaction.span_recorder.spans.last
        expect(request_span.description).to eq("MULTI, SET key, INCR counter, EXEC")
      end
    end
  end

  context "with tracing disabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 0.0
      end
    end

    context "calling Redis SET command" do
      let(:result) { redis.set("key", "value") }

      it "works as usual" do
        expect(result).to eq("OK")
      end
    end
  end
end
