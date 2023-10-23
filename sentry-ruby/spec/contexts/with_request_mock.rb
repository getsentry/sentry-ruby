# because our patch on Net::HTTP is relatively low-level, we need to stub methods on socket level
# which is not supported by most of the http mocking library
# so we need to put something together ourselves
RSpec.shared_context "with request mock" do
  class FakeSocket < StringIO
    def setsockopt(*args); end
  end

  before do
    allow(TCPSocket).to receive(:open).and_return(FakeSocket.new)
  end

  def stub_request(fake_response, &block)
    allow_any_instance_of(Net::HTTP).to receive(:connect)
    allow_any_instance_of(Net::HTTP).to receive(:transport_request) do |http_obj, request|
      block.call(request, http_obj) if block
    end.and_return(fake_response)
  end

  def build_fake_response(status, body: {}, headers: {})
    Net::HTTPResponse.new("1.0", status, "").tap do |response|
      headers.each do |k, v|
        response[k] = v
      end

      # stubbing body to avoid dealing with socket and io issues
      allow(response).to receive(:body).and_return(JSON.generate(body))
    end
  end

  def stub_sentry_response
    # use bad request as an example is easier for verifying with error messages
    stub_request(build_fake_response("400", body: { data: "bad sentry DSN public key" }))
  end

  def stub_normal_response(code: "200", &block)
    stub_request(build_fake_response(code), &block)
  end
end
