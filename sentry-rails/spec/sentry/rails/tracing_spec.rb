require "spec_helper"

RSpec.describe Sentry::Rails::Tracing, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:event) do
    transport.events.last.to_json_compatible
  end

  after do
    transport.events = []

    described_class.unsubscribe_tracing_events
    described_class.remove_active_support_notifications_patch
  end

  context "with traces_sample_rate set" do
    before do
      expect(described_class).to receive(:subscribe_tracing_events).and_call_original

      make_basic_app do |config|
        config.traces_sample_rate = 1.0
      end
    end

    it "records transaction with exception" do
      get "/posts"

      expect(transport.events.count).to eq(2)

      event = transport.events.first.to_hash
      transaction = transport.events.last.to_hash

      expect(event.dig(:contexts, :trace, :trace_id).length).to eq(32)
      expect(event.dig(:contexts, :trace, :trace_id)).to eq(transaction.dig(:contexts, :trace, :trace_id))

      expect(transaction[:type]).to eq("transaction")
      expect(transaction.dig(:contexts, :trace, :op)).to eq("rails.request")
      parent_span_id = transaction.dig(:contexts, :trace, :span_id)
      expect(transaction[:spans].count).to eq(2)

      first_span = transaction[:spans][0]
      expect(first_span[:op]).to eq("sql.active_record")
      expect(first_span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(first_span[:parent_span_id]).to eq(parent_span_id)

      # this is to make sure we calculate the timestamp in the correct scale (second instead of millisecond)
      expect(first_span[:timestamp] - first_span[:start_timestamp]).to be_between(10.0 / 1_000_000, 10.0 / 1000)

      second_span = transaction[:spans][1]
      expect(second_span[:op]).to eq("process_action.action_controller")
      expect(second_span[:description]).to eq("PostsController#index")
      expect(second_span[:parent_span_id]).to eq(parent_span_id)
    end

    it "records transaction alone" do
      p = Post.create!

      get "/posts/#{p.id}"

      expect(transport.events.count).to eq(1)

      transaction = transport.events.last.to_hash

      expect(transaction[:type]).to eq("transaction")
      expect(transaction.dig(:contexts, :trace, :op)).to eq("rails.request")
      parent_span_id = transaction.dig(:contexts, :trace, :span_id)
      expect(transaction[:spans].count).to eq(3)

      first_span = transaction[:spans][0]
      expect(first_span[:op]).to eq("sql.active_record")
      expect(first_span[:description].squeeze("\s")).to eq(
        'SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? LIMIT ?'
      )
      expect(first_span[:parent_span_id]).to eq(parent_span_id)

      # this is to make sure we calculate the timestamp in the correct scale (second instead of millisecond)
      expect(first_span[:timestamp] - first_span[:start_timestamp]).to be_between(10.0 / 1_000_000, 10.0 / 1000)

      last_span = transaction[:spans][2]
      expect(last_span[:data][:payload].keys).not_to include(:headers)
      expect(last_span[:data][:payload].keys).not_to include(:request)
      expect(last_span[:data][:payload].keys).not_to include(:response)
      expect(last_span[:op]).to eq("process_action.action_controller")
      expect(last_span[:description]).to eq("PostsController#show")
      expect(last_span[:parent_span_id]).to eq(parent_span_id)
    end
  end

  context "with sprockets-rails" do
    let(:string_io) { StringIO.new }
    let(:logger) do
      ::Logger.new(string_io)
    end

    before do
      require "sprockets/railtie"

      make_basic_app do |config, app|
        app.config.public_file_server.enabled = true
        config.traces_sample_rate = 1.0
        config.logger = logger
      end
    end

    it "doesn't record requests for asset files" do
      get "/assets/application-ad022df6f1289ec07a560bb6c9a227ecf7bdd5a5cace5e9a8cdbd50b454931fb.css"

      expect(response).to have_http_status(:not_found)
      expect(transport.events).to be_empty
      expect(string_io.string).not_to match(/\[Tracing\] Starting <rails\.request>/)
    end
  end

  context "with config.public_file_server.enabled = true" do
    let(:string_io) { StringIO.new }
    let(:logger) do
      ::Logger.new(string_io)
    end

    before do
      make_basic_app do |config, app|
        app.config.public_file_server.enabled = true
        config.traces_sample_rate = 1.0
        config.logger = logger
      end
    end

    it "doesn't record requests for static files" do
      get "/static.html"

      expect(response).to have_http_status(:ok)
      expect(transport.events).to be_empty
      expect(string_io.string).not_to match(/\[Tracing\] Starting <rails\.request>/)
    end

    it "doesn't get messed up by previous exception" do
      get "/exception"

      expect(transport.events.count).to eq(2)

      p = Post.create!
      get "/posts/#{p.id}"

      expect(transport.events.count).to eq(3)

      transaction = transport.events.last.to_hash

      expect(transaction[:type]).to eq("transaction")
      expect(transaction[:transaction]).to eq("PostsController#show")
      second_span = transaction[:spans][2]
      expect(second_span[:description]).to eq("PostsController#show")
    end

    context "with sentry-trace header" do
      let(:external_transaction) do
        Sentry::Transaction.new(
          op: "pageload",
          status: "ok",
          sampled: true,
          name: "a/path",
          hub: Sentry.get_current_hub
        )
      end

      it "inherits trace info from the transaction" do
        p = Post.create!

        get "/posts/#{p.id}", headers: { "sentry-trace" => external_transaction.to_sentry_trace }

        transaction = transport.events.last
        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
        expect(transaction.contexts.dig(:trace, :op)).to eq("rails.request")
        expect(transaction.spans.count).to eq(3)

        # should inherit information from the external_transaction
        expect(transaction.contexts.dig(:trace, :trace_id)).to eq(external_transaction.trace_id)
        expect(transaction.contexts.dig(:trace, :parent_span_id)).to eq(external_transaction.span_id)
        expect(transaction.contexts.dig(:trace, :span_id)).not_to eq(external_transaction.span_id)
      end
    end
  end

  context "without traces_sample_rate set" do
    before do
      expect(described_class).not_to receive(:subscribe_tracing_events)

      make_basic_app
    end

    it "doesn't record any transaction" do
      get "/posts"

      expect(transport.events.count).to eq(1)
    end
  end
end
