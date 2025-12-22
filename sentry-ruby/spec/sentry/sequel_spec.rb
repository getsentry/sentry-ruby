# frozen_string_literal: true

require "spec_helper"
require "sequel"

# Load the sequel patch
require "sentry/sequel"

RSpec.describe Sentry::Sequel do
  let(:db) do
    if RUBY_ENGINE == "jruby"
      Sequel.connect("jdbc:sqlite::memory:")
    else
      Sequel.sqlite
    end
  end

  before do
    # Create a simple test table
    db.create_table :posts do
      primary_key :id
      String :title
    end

    # Trigger Sequel's internal initialization (e.g., SELECT sqlite_version())
    db[:posts].count
  end

  after do
    db.drop_table?(:posts)
  end

  context "with tracing enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.enabled_patches << :sequel
      end

      # Apply patch to this specific database instance
      db.extension(:sentry)
    end

    it "records a span for SELECT queries" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      db[:posts].all

      spans = transaction.span_recorder.spans
      db_span = spans.find { |span| span.op == "db.sql.sequel" }

      expect(db_span).not_to be_nil
      expect(db_span.description).to include("SELECT")
      expect(db_span.description).to include("posts")
      expect(db_span.origin).to eq("auto.db.sequel")
    end

    it "records a span for INSERT queries" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      db[:posts].insert(title: "Hello World")

      spans = transaction.span_recorder.spans
      db_span = spans.find { |span| span.op == "db.sql.sequel" && span.description&.include?("INSERT") }

      expect(db_span).not_to be_nil
      expect(db_span.description).to include("INSERT")
      expect(db_span.description).to include("posts")
    end

    it "records a span for UPDATE queries" do
      db[:posts].insert(title: "Hello World")

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      db[:posts].where(title: "Hello World").update(title: "Updated")

      spans = transaction.span_recorder.spans
      db_span = spans.find { |span| span.op == "db.sql.sequel" && span.description&.include?("UPDATE") }

      expect(db_span).not_to be_nil
      expect(db_span.description).to include("UPDATE")
      expect(db_span.description).to include("posts")
    end

    it "records a span for DELETE queries" do
      db[:posts].insert(title: "Hello World")

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      db[:posts].where(title: "Hello World").delete

      spans = transaction.span_recorder.spans
      db_span = spans.find { |span| span.op == "db.sql.sequel" && span.description&.include?("DELETE") }

      expect(db_span).not_to be_nil
      expect(db_span.description).to include("DELETE")
      expect(db_span.description).to include("posts")
    end

    it "sets span data with database information" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      db[:posts].all

      spans = transaction.span_recorder.spans
      db_span = spans.find { |span| span.op == "db.sql.sequel" }

      expect(db_span.data["db.system"]).to eq("sqlite")
    end

    it "sets correct timestamps on span" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      db[:posts].all

      spans = transaction.span_recorder.spans
      db_span = spans.find { |span| span.op == "db.sql.sequel" }

      expect(db_span.start_timestamp).not_to be_nil
      expect(db_span.timestamp).not_to be_nil
      expect(db_span.start_timestamp).to be < db_span.timestamp
    end
  end

  context "without active transaction" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.enabled_patches << :sequel
      end

      db.extension(:sentry)
    end

    it "does not create spans when no transaction is active" do
      # No transaction started
      result = db[:posts].all

      # Query should still work
      expect(result).to eq([])
    end
  end

  context "when Sentry is not initialized" do
    before do
      # Don't initialize Sentry
      db.extension(:sentry)
    end

    it "does not interfere with normal database operations" do
      result = db[:posts].insert(title: "Test")
      expect(result).to eq(1)

      posts = db[:posts].all
      expect(posts.length).to eq(1)
      expect(posts.first[:title]).to eq("Test")
    end
  end
end
