require "spec_helper"

RSpec.describe :redis_logger do
  let(:redis) { Redis.new(host: "127.0.0.1") }

  before do
    perform_basic_setup do |config|
      config.breadcrumbs_logger = [:redis_logger]
    end
  end

  context "config.send_default_pii = false" do
    before { Sentry.configuration.send_default_pii = false }

    it "adds Redis command breadcrumb with command and key" do
      result = redis.set("key", "value")

      expect(result).to eq("OK")
      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        category: "db.redis",
        data: { commands: [{ command: "SET", key: "key" }], server: "127.0.0.1:6379/0" }
      )
    end
  end

  context "config.send_default_pii = true" do
    before { Sentry.configuration.send_default_pii = true }

    it "adds Redis command breadcrumb with command, key and arguments" do
      result = redis.set("key", "value")

      expect(result).to eq("OK")
      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        category: "db.redis",
        data: { commands: [{ command: "SET", key: "key", arguments: "value" }], server: "127.0.0.1:6379/0" }
      )
    end

    it "logs complex Redis commands with multiple arguments" do
      redis.hmset("hashkey", "key1", "value1", "key2", "value2")

      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        data: include(commands: [{ command: "HMSET", key: "hashkey", arguments: "key1 value1 key2 value2" }])
      )
    end

    it "logs Redis command with options" do
      redis.zrangebyscore("sortedsetkey", "1", "2", with_scores: true, limit: [0, 10])

      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        data: include(commands: [{ command: "ZRANGEBYSCORE", key: "sortedsetkey", arguments: "1 2 WITHSCORES LIMIT 0 10" }])
      )
    end
  end

  context "calling Redis command which doesn't require a key" do
    let(:result) { redis.info }

    it "doesn't cause an error" do
      expect(result.key?("uptime_in_days")).to eq(true)
      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        category: "db.redis",
        data: { commands: [{ command: "INFO", key: nil }], server: "127.0.0.1:6379/0" }
      )
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

      expect(result).to contain_exactly("OK", kind_of(Numeric))
      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        category: "db.redis",
        data: {
          commands: [
            { command: "MULTI", key: nil },
            { command: "SET",   key: "key" },
            { command: "INCR",  key: "counter" },
            { command: "EXEC",  key: nil }
          ],
          server: "127.0.0.1:6379/0"
        }
      )
    end
  end

  context "when DSN is nil" do
    before do
      Sentry.configuration.instance_variable_set(:@dsn, nil)
    end

    it "doesn't cause an error" do
      result = redis.set("key", "value")

      expect(result).to eq("OK")
      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        category: "db.redis",
        data: { commands: [{ command: "SET", key: "key" }], server: "127.0.0.1:6379/0" }
      )
    end
  end
end
