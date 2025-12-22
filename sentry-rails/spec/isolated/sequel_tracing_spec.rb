# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "SequelTracing"
rescue LoadError
end

require "sequel"
require "sentry/sequel"

require_relative "../dummy/test_rails_app/app/controllers/sequel_users_controller"

RSpec.describe "Sequel Tracing with Rails", type: :request do
  before(:all) do
    if RUBY_ENGINE == "jruby"
      SEQUEL_DB = Sequel.connect("jdbc:sqlite::memory:")
    else
      SEQUEL_DB = Sequel.sqlite
    end

    SEQUEL_DB.create_table :users do
      primary_key :id
      String :name
      String :email
    end

    SEQUEL_DB[:users].count
    SEQUEL_DB.extension(:sentry)
  end

  after(:all) do
    SEQUEL_DB.drop_table?(:users)
    Object.send(:remove_const, :SEQUEL_DB)
  end

  before do
    make_basic_app do |config, app|
      config.traces_sample_rate = 1.0
      config.enabled_patches << :sequel
    end
  end

  let(:transport) { Sentry.get_current_client.transport }

  describe "SELECT queries" do
    it "creates a transaction with Sequel span for index action" do
      get "/sequel/users"

      expect(response).to have_http_status(:ok)
      expect(transport.events.count).to eq(1)

      transaction = transport.events.last.to_h

      expect(transaction[:type]).to eq("transaction")
      expect(transaction.dig(:contexts, :trace, :op)).to eq("http.server")

      sequel_span = transaction[:spans].find { |span| span[:op] == "db.sql.sequel" }

      expect(sequel_span).not_to be_nil
      expect(sequel_span[:description]).to include("SELECT")
      expect(sequel_span[:description]).to include("users")
      expect(sequel_span[:origin]).to eq("auto.db.sequel")
      expect(sequel_span[:data]["db.system"]).to eq("sqlite")
    end
  end

  describe "INSERT queries" do
    it "creates a transaction with Sequel span for create action" do
      post "/sequel/users", params: { name: "John Doe", email: "john@example.com" }

      expect(response).to have_http_status(:created)

      transaction = transport.events.last.to_h
      expect(transaction[:type]).to eq("transaction")

      insert_span = transaction[:spans].find do |span|
        span[:op] == "db.sql.sequel" && span[:description]&.include?("INSERT")
      end

      expect(insert_span).not_to be_nil
      expect(insert_span[:description]).to include("INSERT")
      expect(insert_span[:description]).to include("users")
      expect(insert_span[:origin]).to eq("auto.db.sequel")
    end
  end

  describe "UPDATE queries" do
    it "creates a transaction with Sequel span for update action" do
      SEQUEL_DB[:users].insert(name: "Jane Doe", email: "jane@example.com")

      put "/sequel/users/1", params: { name: "Jane Smith" }

      expect(response).to have_http_status(:ok)

      transaction = transport.events.last.to_h

      update_span = transaction[:spans].find do |span|
        span[:op] == "db.sql.sequel" && span[:description]&.include?("UPDATE")
      end

      expect(update_span).not_to be_nil
      expect(update_span[:description]).to include("UPDATE")
      expect(update_span[:description]).to include("users")
    end
  end

  describe "DELETE queries" do
    it "creates a transaction with Sequel span for delete action" do
      SEQUEL_DB[:users].insert(name: "Delete Me", email: "delete@example.com")

      delete "/sequel/users/1"

      expect(response).to have_http_status(:no_content)

      transaction = transport.events.last.to_h

      delete_span = transaction[:spans].find do |span|
        span[:op] == "db.sql.sequel" && span[:description]&.include?("DELETE")
      end

      expect(delete_span).not_to be_nil
      expect(delete_span[:description]).to include("DELETE")
      expect(delete_span[:description]).to include("users")
    end
  end

  describe "exception handling" do
    it "creates both error event and transaction with Sequel span" do
      get "/sequel/exception"

      expect(response).to have_http_status(:internal_server_error)

      expect(transport.events.count).to eq(2)

      error_event = transport.events.first.to_h
      transaction = transport.events.last.to_h

      expect(error_event[:exception][:values].first[:type]).to eq("RuntimeError")
      expect(error_event[:exception][:values].first[:value]).to include("Something went wrong!")

      sequel_span = transaction[:spans].find { |span| span[:op] == "db.sql.sequel" }
      expect(sequel_span).not_to be_nil
      expect(sequel_span[:description]).to include("SELECT")

      expect(error_event.dig(:contexts, :trace, :trace_id)).to eq(
        transaction.dig(:contexts, :trace, :trace_id)
      )
    end
  end

  describe "span timing" do
    it "records proper start and end timestamps" do
      get "/sequel/users"

      transaction = transport.events.last.to_h
      sequel_span = transaction[:spans].find { |span| span[:op] == "db.sql.sequel" }

      expect(sequel_span[:start_timestamp]).not_to be_nil
      expect(sequel_span[:timestamp]).not_to be_nil
      expect(sequel_span[:start_timestamp]).to be < sequel_span[:timestamp]
    end
  end

  describe "Sequel and ActiveRecord coexistence" do
    it "records spans for both database systems in the same application" do
      Post.create!(title: "Test Post")

      SEQUEL_DB[:users].insert(name: "Sequel User", email: "sequel@example.com")

      transport.events.clear

      get "/sequel/users"

      expect(response).to have_http_status(:ok)

      transaction = transport.events.last.to_h
      sequel_spans = transaction[:spans].select { |span| span[:op] == "db.sql.sequel" }

      expect(sequel_spans.length).to be >= 1
      expect(sequel_spans.first[:data]["db.system"]).to eq("sqlite")
    end

    it "records ActiveRecord spans separately from Sequel spans" do
      transport.events.clear

      get "/posts"

      expect(response).to have_http_status(:internal_server_error) # raises "foo" in PostsController#index

      transaction = transport.events.last.to_h

      ar_spans = transaction[:spans].select { |span| span[:op] == "db.sql.active_record" }
      sequel_spans = transaction[:spans].select { |span| span[:op] == "db.sql.sequel" }

      expect(ar_spans.length).to be >= 1
      expect(sequel_spans.length).to eq(0)
    end
  end
end
