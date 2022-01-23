require "spec_helper"
require "fakeredis"
# After requiring a Redis client (fakeredis), we need to forceably reload the Redis client patch:
load "sentry/redis.rb"

RSpec.describe :redis_logger do
  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end
  let(:redis) do
    Redis.new
  end

  before do
    perform_basic_setup do |config|
      config.breadcrumbs_logger = [:redis_logger]
      config.logger = logger
    end
  end

  it "adds Redis command breadcrumb with command and key" do
    result = redis.set("key", "value")

    expect(result).to eq("OK")
    expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
      category: "db.redis.command",
      data: { commands: [{ command: "SET", key: "key" }], server: "127.0.0.1:6379/0" }
    )
  end

  context "calling Redis command which doesn't require a key" do
    let(:result) { redis.info }

    it "doesn't cause an error" do
      expect(result).to include("uptime_in_days" => 0)
      expect(Sentry.get_current_scope.breadcrumbs.peek).to have_attributes(
        category: "db.redis.command",
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
        category: "db.redis.command",
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
        category: "db.redis.command",
        data: { commands: [{ command: "SET", key: "key" }], server: "127.0.0.1:6379/0" }
      )
    end
  end
end
