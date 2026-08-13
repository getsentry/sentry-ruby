# frozen_string_literal: true

return unless defined?(Rack)

RSpec.describe Sentry::RequestInterface do
  let(:env) { Rack::MockRequest.env_for("/test") }
  let(:send_default_pii) { false }
  let(:configuration) do
    Sentry::Configuration.new do |config|
      config.send_default_pii = send_default_pii
    end
  end
  let(:data_collection) { configuration.data_collection }
  let(:rack_env_whitelist) { Sentry::Configuration::RACK_ENV_WHITELIST_DEFAULT }

  subject do
    described_class.new(
      env: env,
      data_collection: data_collection,
      rack_env_whitelist: rack_env_whitelist
    )
  end

  describe "rack_env_whitelist" do
    let(:additional_env) { { "random_param" => "text", "query_string" => "test" } }

    before do
      env.merge!(additional_env)
    end

    it 'excludes non whitelisted params from rack env' do
      expect(subject.env).to_not include(additional_env)
    end

    context "with provided whitelist" do
      let(:rack_env_whitelist) { %w[random_param query_string] }

      it 'formats rack env according to the provided whitelist' do
        expect(subject.env).to eq(additional_env)
      end
    end

    context "with empty whitelist" do
      let(:rack_env_whitelist) { [] }

      it 'keeps the original env values intact' do
        expect(subject.env).to include(env)
      end
    end
  end

  describe 'format headers' do
    let(:additional_headers) { { "HTTP_VERSION" => "HTTP/1.1", "HTTP_COOKIE" => "test", "HTTP_X_REQUEST_ID" => "12345678" } }
    let(:env) { Rack::MockRequest.env_for("/test", additional_headers) }

    it 'transforms headers to conform with the interface' do
      expect(subject.headers).to include("Version" => "HTTP/1.1", "X-Request-Id" => "12345678")
      expect(subject.headers).to include("Cookie" => "[Filtered]")
    end

    context 'from Rails middleware' do
      let(:additional_headers) { { "action_dispatch.request_id" => "12345678" } }

      it 'transforms headers to conform with the interface' do
        expect(subject.headers).to include("X-Request-Id" => "12345678")
        expect(subject.headers).not_to include("Cookie")
      end
    end

    context 'with special characters' do
      let(:additional_headers) { { "HTTP_FOO" => "Tekirda\xC4" } }

      it "doesn't cause any issue" do
        json = JSON.generate(subject.to_h)

        expect(JSON.parse(json)["headers"]).to include("Foo"=>"Tekirda�")
      end
    end

    context 'with additional env variables' do
      let(:mock) { double }
      let(:env) { { "some.variable" => mock } }

      it 'does not call #to_s for unnecessary env variables' do
        expect(mock).not_to receive(:to_s)

        subject
      end
    end
  end

  it "doesn't capture cookies info" do
    env.merge!(::Rack::RACK_REQUEST_COOKIE_HASH => { "my" => "cookies!" })

    expect(subject.cookies).to eq({})
    expect(subject.env["COOKIE"]).to eq(nil)
  end

  describe "headers filtering" do
    it "filters out HTTP_COOKIE header" do
      env.merge!("HTTP_COOKIE" => "cookies!")

      expect(subject.headers["Cookie"]).to eq("[Filtered]")
    end

    it "filters out non-http headers" do
      expect(subject.headers["Request-Method"]).to eq(nil)
    end

    it "doesn't filter out CONTENT_TYPE or CONTENT_LENGTH headers" do
      env.merge!(
        "CONTENT_LENGTH" => 10,
        "CONTENT_TYPE" => "text/html"
      )

      expect(subject.headers["Content-Length"]).to eq("10")
      expect(subject.headers["Content-Type"]).to eq("text/html")
    end

    it 'does not ignore version headers which do not match SERVER_PROTOCOL' do
      env.merge!("SERVER_PROTOCOL" => "HTTP/1.1", "HTTP_VERSION" => "HTTP/2.0")

      expect(subject.headers["Version"]).to eq("HTTP/2.0")
    end

    it 'retains any literal "HTTP-" in the actual header name' do
      env.merge!("HTTP_HTTP_CUSTOM_HTTP_HEADER" => "test")
      expect(subject.headers).to include("Http-Custom-Http-Header" => "test")
    end

    it "filters Authorization header" do
      env.merge!("HTTP_AUTHORIZATION" => "Basic YWxhZGRpbjpvcGVuc2VzYW1l")

      expect(subject.headers["Authorization"]).to eq("[Filtered]")
    end

    it 'does not fail if an object in the env cannot be cast to string' do
      obj = Class.new do
        def to_s
          raise 'Could not stringify object!'
        end
      end.new

      env.merge!("HTTP_FOO" => "BAR", "rails_object" => obj)

      expect do
        described_class.new(
          env: env,
          data_collection: data_collection,
          rack_env_whitelist: rack_env_whitelist
        )
      end.to_not raise_error
    end
  end

  it "doesn't store request body by default" do
    env.merge!("REQUEST_METHOD" => "POST", ::Rack::RACK_INPUT => StringIO.new("data=ignore me"))

    expect(subject.data).to eq(nil)
  end

  it "doesn't store request body by default" do
    env.merge!(::Rack::RACK_INPUT => StringIO.new("ignore me"))

    expect(subject.data).to eq(nil)
  end

  it "doesn't store query_string by default" do
    env.merge!("QUERY_STRING" => "token=xxxx")

    expect(subject.query_string).to eq(nil)
  end

  it "doesn't fail on a malformed query string" do
    env.merge!("QUERY_STRING" => "a=%")

    expect { subject }.not_to raise_error
    expect(subject.query_string).to eq(nil)
  end

  it "doesn't fail on query parameters with conflicting types" do
    env.merge!("QUERY_STRING" => "a[]=1&a[x]=2")

    expect { subject }.not_to raise_error
    expect(subject.query_string).to eq(nil)
  end

  describe "data_collection" do
    context "when cookies are disabled" do
      before do
        data_collection.cookies.mode = :off
        env.merge!(::Rack::RACK_REQUEST_COOKIE_HASH => { "session" => "secret", "name" => "Ada" })
      end

      it "does not collect cookies" do
        expect(subject.cookies).to eq({})
      end
    end

    context "when cookies use an allow list" do
      before do
        data_collection.cookies.mode = :allow_list
        data_collection.cookies.terms = ["name"]
        env.merge!(::Rack::RACK_REQUEST_COOKIE_HASH => { "session" => "secret", "name" => "Ada" })
      end

      it "only collects allowed cookies" do
        expect(subject.cookies).to eq("session" => "[Filtered]", "name" => "Ada")
      end
    end

    context "when cookies use a deny list" do
      before do
        data_collection.cookies.mode = :deny_list
        data_collection.cookies.terms = ["private"]
        env.merge!(::Rack::RACK_REQUEST_COOKIE_HASH => { "private_data" => "secret", "name" => "Ada" })
      end

      it "filters matching cookies and collects the others" do
        expect(subject.cookies).to eq("private_data" => "[Filtered]", "name" => "Ada")
      end
    end

    context "when query parameters use an allow list" do
      before do
        data_collection.url_query_params.mode = :allow_list
        data_collection.url_query_params.terms = ["page"]
        env.merge!("QUERY_STRING" => "token=secret&page=2")
      end

      it "only collects allowed query parameters" do
        expect(subject.query_string).to eq("token" => "[Filtered]", "page" => "2")
      end
    end

    context "when query parameters use a deny list" do
      before do
        data_collection.url_query_params.mode = :deny_list
        data_collection.url_query_params.terms = ["private"]
        env.merge!("QUERY_STRING" => "private_data=secret&page=2")
      end

      it "filters matching query parameters and collects the others" do
        expect(subject.query_string).to eq("private_data" => "[Filtered]", "page" => "2")
      end
    end

    context "when request headers use an allow list" do
      before do
        data_collection.http_headers.request.mode = :allow_list
        data_collection.http_headers.request.terms = ["public"]
        env.merge!(
          "HTTP_X_PUBLIC" => "visible",
          "HTTP_X_PRIVATE" => "private",
          "HTTP_AUTHORIZATION" => "secret"
        )
      end

      it "only collects allowed headers and always filters sensitive values" do
        expect(subject.headers).to include(
          "X-Public" => "visible",
          "X-Private" => "[Filtered]",
          "Authorization" => "[Filtered]"
        )
      end
    end

    context "when request headers use a deny list" do
      before do
        data_collection.http_headers.request.mode = :deny_list
        data_collection.http_headers.request.terms = ["private"]
        env.merge!(
          "HTTP_X_PUBLIC" => "visible",
          "HTTP_X_PRIVATE" => "private",
          "HTTP_AUTHORIZATION" => "secret"
        )
      end

      it "filters matching headers, collects the others, and always filters sensitive values" do
        expect(subject.headers).to include(
          "X-Public" => "visible",
          "X-Private" => "[Filtered]",
          "Authorization" => "[Filtered]"
        )
      end
    end

    context "when incoming request bodies are configured" do
      before do
        data_collection.http_bodies = [:incoming_request]
        env.merge!(
          "REQUEST_METHOD" => "POST",
          ::Rack::RACK_INPUT => StringIO.new("name=Ada")
        )
      end

      it "collects the request body" do
        expect(subject.data).to eq("name" => "Ada")
      end

      it "collects and filters a JSON request body" do
        env.merge!(
          "CONTENT_TYPE" => "application/json",
          ::Rack::RACK_INPUT => StringIO.new('{"password":"secret","name":"Ada"}')
        )

        expect(subject.data).to eq("password" => "[Filtered]", "name" => "Ada")
      end
    end

    context "when incoming request bodies are not configured" do
      before do
        data_collection.http_bodies = [:outgoing_request]
        env.merge!(
          "REQUEST_METHOD" => "POST",
          ::Rack::RACK_INPUT => StringIO.new("name=Ada")
        )
      end

      it "does not collect the request body" do
        expect(subject.data).to be_nil
      end
    end

    context "when request data collection is disabled" do
      let(:rack_env_whitelist) { [] }

      before do
        data_collection.cookies.mode = :off
        data_collection.http_headers.request.mode = :off
        data_collection.http_bodies = []
        data_collection.url_query_params.mode = :off
        env.merge!(
          "QUERY_STRING" => "page=2",
          "HTTP_X_PUBLIC" => "visible",
          ::Rack::RACK_REQUEST_COOKIE_HASH => { "name" => "Ada" },
          ::Rack::RACK_INPUT => StringIO.new("name=Ada")
        )
      end

      it "does not collect cookies, query parameters, headers, env, or body" do
        expect(subject.cookies).to eq({})
        expect(subject.query_string).to be_nil
        expect(subject.headers).to eq({})
        expect(subject.env).to eq({})
        expect(subject.data).to be_nil
      end
    end
  end

  context "with config.send_default_pii = true" do
    let(:send_default_pii) { true }

    it "stores cookies" do
      env.merge!(::Rack::RACK_REQUEST_COOKIE_HASH => { "my" => "cookies!" })

      expect(subject.cookies).to eq({ "my" => "cookies!" })
    end

    it "stores and filters form data" do
      env.merge!(
        "REQUEST_METHOD" => "POST",
        ::Rack::RACK_INPUT => StringIO.new("password=secret&name=Ada")
      )

      expect(subject.data).to eq("password" => "[Filtered]", "name" => "Ada")
    end

    it "stores and filters query string values" do
      env.merge!("QUERY_STRING" => "token=xxxx&page=2")

      expect(subject.query_string).to eq("token" => "[Filtered]", "page" => "2")
    end

    it "stores text request bodies" do
      env.merge!("CONTENT_TYPE" => "application/text", ::Rack::RACK_INPUT => StringIO.new("catch me"))

      expect(subject.data).to eq("catch me")
    end

    it "filters invalid JSON request bodies" do
      env.merge!("CONTENT_TYPE" => "application/json", ::Rack::RACK_INPUT => StringIO.new("invalid"))

      expect(subject.data).to include("unexpected")
    end

    it "filters sensitive values in JSON request bodies" do
      env.merge!(
        "CONTENT_TYPE" => "application/json",
        ::Rack::RACK_INPUT => StringIO.new('{"password":"secret","name":"Ada"}')
      )

      expect(subject.data).to eq("password" => "[Filtered]", "name" => "Ada")
    end

    ["null", "true", "42", '"text"', '["value"]'].each do |body|
      it "stores non-object JSON request body: #{body}" do
        env.merge!("CONTENT_TYPE" => "application/json", ::Rack::RACK_INPUT => StringIO.new(body))

        expect(subject.data).to eq(JSON.parse(body))
      end
    end

    it "does not try to read non rewindable body" do
      env.merge!(::Rack::RACK_INPUT => double)

      expect(subject.data).to eq("Skipped non-rewindable request body")
    end

    it "stores rewindable text bodies" do
      dbl = double
      allow(dbl).to receive(:rewind)
      allow(dbl).to receive(:read).and_return("stuff")
      env.merge!("CONTENT_TYPE" => "application/text", ::Rack::RACK_INPUT => dbl)

      expect(subject.data).to eq("stuff")
    end

    it "Authorization header is sensitive and still filtered" do
      env.merge!("HTTP_AUTHORIZATION" => "Basic YWxhZGRpbjpvcGVuc2VzYW1l")

      expect(subject.headers["Authorization"]).to eq("[Filtered]")
    end

    it "force encodes request body to avoid encoding issue" do
      env.merge!(::Rack::RACK_INPUT => StringIO.new("あ"))

      expect do
        JSON.generate(subject.to_h)
      end.not_to raise_error
    end

    it "doesn't remove ip address headers" do
      ip = "1.1.1.1"

      env.merge!(
        "REMOTE_ADDR" => ip,
        "HTTP_CLIENT_IP" => ip,
        "HTTP_X_REAL_IP" => ip,
        "HTTP_X_FORWARDED_FOR" => ip
      )

      expect(subject.env).to include("REMOTE_ADDR")
      expect(subject.headers.keys).to include("Client-Ip")
      expect(subject.headers.keys).to include("X-Real-Ip")
      expect(subject.headers.keys).to include("X-Forwarded-For")
    end
  end
end
