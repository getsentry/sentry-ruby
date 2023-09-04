require "spec_helper"

RSpec.describe Sentry::Rails::Tracing, type: :request do
  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:event) do
    transport.events.last.to_json_compatible
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

      expect(response).to have_http_status(:internal_server_error)
      expect(transport.events.count).to eq(2)

      event = transport.events.first.to_hash
      transaction = transport.events.last.to_hash

      expect(event.dig(:contexts, :trace, :trace_id).length).to eq(32)
      expect(event.dig(:contexts, :trace, :trace_id)).to eq(transaction.dig(:contexts, :trace, :trace_id))

      expect(transaction[:type]).to eq("transaction")
      expect(transaction.dig(:contexts, :trace, :op)).to eq("http.server")
      parent_span_id = transaction.dig(:contexts, :trace, :span_id)
      expect(transaction[:spans].count).to eq(2)

      first_span = transaction[:spans][0]
      expect(first_span[:op]).to eq("view.process_action.action_controller")
      expect(first_span[:description]).to eq("PostsController#index")
      expect(first_span[:parent_span_id]).to eq(parent_span_id)
      expect(first_span[:status]).to eq("internal_error")
      expect(first_span[:data].keys).to match_array(["http.response.status_code", :format, :method, :path, :params])

      second_span = transaction[:spans][1]
      expect(second_span[:op]).to eq("db.sql.active_record")
      expect(second_span[:description]).to eq("SELECT \"posts\".* FROM \"posts\"")
      expect(second_span[:parent_span_id]).to eq(first_span[:span_id])

      # this is to make sure we calculate the timestamp in the correct scale (second instead of millisecond)
      expect(second_span[:timestamp] - second_span[:start_timestamp]).to be_between(10.0 / 1_000_000, 10.0 / 1000)
    end

    it "records transaction alone" do
      p = Post.create!

      get "/posts/#{p.id}"

      expect(response).to have_http_status(:ok)
      expect(transport.events.count).to eq(1)

      transaction = transport.events.last.to_hash

      expect(transaction[:type]).to eq("transaction")
      expect(transaction.dig(:contexts, :trace, :op)).to eq("http.server")
      parent_span_id = transaction.dig(:contexts, :trace, :span_id)
      expect(transaction[:spans].count).to eq(3)

      first_span = transaction[:spans][0]
      expect(first_span[:data].keys).to match_array(["http.response.status_code", :format, :method, :path, :params])
      expect(first_span[:op]).to eq("view.process_action.action_controller")
      expect(first_span[:description]).to eq("PostsController#show")
      expect(first_span[:parent_span_id]).to eq(parent_span_id)
      expect(first_span[:status]).to eq("ok")


      second_span = transaction[:spans][1]
      expect(second_span[:op]).to eq("db.sql.active_record")
      expect(second_span[:description].squeeze("\s")).to eq(
        'SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? LIMIT ?'
      )
      expect(second_span[:parent_span_id]).to eq(first_span[:span_id])

      # this is to make sure we calculate the timestamp in the correct scale (second instead of millisecond)
      expect(second_span[:timestamp] - second_span[:start_timestamp]).to be_between(10.0 / 1_000_000, 10.0 / 1000)

      third_span = transaction[:spans][2]
      expect(third_span[:op]).to eq("template.render_template.action_view")
      expect(third_span[:description].squeeze("\s")).to eq("text template")
      expect(third_span[:parent_span_id]).to eq(first_span[:span_id])
    end

    it "doesn't mess with custom instrumentations" do
      get "/with_custom_instrumentation"
      expect(response).to have_http_status(:ok)

      expect(transport.events.count).to eq(1)
    end
  end

  context "with instrumenter :otel" do
    before do
      make_basic_app do |config|
        config.traces_sample_rate = 1.0
        config.instrumenter = :otel
      end
    end

    it "doesn't do any tracing" do
      p = Post.create!
      get "/posts/#{p.id}"

      expect(response).to have_http_status(:ok)
      expect(transport.events.count).to eq(0)
    end
  end

  context "with sprockets-rails" do
    let(:string_io) { StringIO.new }
    let(:logger) do
      ::Logger.new(string_io)
    end

    context "with default setup" do
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

    context "with custom assets_regexp config" do
      before do
        require "sprockets/railtie"

        make_basic_app do |config, app|
          app.config.public_file_server.enabled = true
          config.traces_sample_rate = 1.0
          config.logger = logger
          config.rails.assets_regexp = %r(/foo/)
        end
      end

      it "accepts customized asset path patterns" do
        get "/foo/application-ad022df6f1289ec07a560bb6c9a227ecf7bdd5a5cace5e9a8cdbd50b454931fb.css"

        expect(response).to have_http_status(:not_found)
        expect(transport.events).to be_empty
        expect(string_io.string).not_to match(/\[Tracing\] Starting <rails\.request>/)

        get "/assets/application-ad022df6f1289ec07a560bb6c9a227ecf7bdd5a5cace5e9a8cdbd50b454931fb.css"

        expect(response).to have_http_status(:not_found)
        expect(transport.events.count).to eq(1)
      end
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
      first_span = transaction[:spans][0]
      expect(first_span[:description]).to eq("PostsController#show")
    end

    context "with sentry-trace and baggage headers" do
      let(:external_transaction) do
        Sentry::Transaction.new(
          op: "pageload",
          status: "ok",
          sampled: true,
          name: "a/path",
          hub: Sentry.get_current_hub
        )
      end

      let(:baggage) do
        "other-vendor-value-1=foo;bar;baz, "\
          "sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
          "sentry-public_key=49d0f7386ad645858ae85020e393bef3, "\
          "sentry-sample_rate=0.01337, "\
          "sentry-user_id=Am%C3%A9lie,  "\
          "other-vendor-value-2=foo;bar;"
      end

      it "inherits trace info from the transaction" do
        p = Post.create!

        headers = { "sentry-trace" => external_transaction.to_sentry_trace, baggage: baggage }
        get "/posts/#{p.id}", headers: headers

        transaction = transport.events.last
        expect(transaction.type).to eq("transaction")
        expect(transaction.timestamp).not_to be_nil
        expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
        expect(transaction.contexts.dig(:trace, :op)).to eq("http.server")
        expect(transaction.spans.count).to eq(3)

        # should inherit information from the external_transaction
        expect(transaction.contexts.dig(:trace, :trace_id)).to eq(external_transaction.trace_id)
        expect(transaction.contexts.dig(:trace, :parent_span_id)).to eq(external_transaction.span_id)
        expect(transaction.contexts.dig(:trace, :span_id)).not_to eq(external_transaction.span_id)

        # should have baggage converted to DSC
        expect(transaction.dynamic_sampling_context).to eq({
          "sample_rate" => "0.01337",
          "public_key" => "49d0f7386ad645858ae85020e393bef3",
          "trace_id" => "771a43a4192642f0b136d5159a501700",
          "user_id" => "Amélie"
        })
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

  context "with traces_sampler set" do
    before do
      expect(described_class).to receive(:subscribe_tracing_events).and_call_original

      make_basic_app do |config|
        config.traces_sampler = lambda do |sampling_context|
          request_env = sampling_context[:env]
          case request_env&.dig('HTTP_USER_AGENT')
          when /node-fetch/
            0.0
          else
            1.0
          end
        end
      end
    end

    context "with sampling condition matches" do
      it "records all transactions" do
        get "/posts"

        expect(transport.events.count).to eq(2)
      end
    end

    context "with sampling condition doesn't matched" do
      it "doesn't records any transactions" do
        get "/posts", headers: { "user-agent" => "node-fetch/1.0" }

        expect(transport.events.count).to eq(1)
      end
    end
  end
end
