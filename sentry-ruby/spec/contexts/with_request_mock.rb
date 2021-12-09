require "webmock"

RSpec.shared_context "with request mock" do
  before { stub_const('Net::BufferedIO', Net::WebMockNetBufferedIO) }

  class FakeSocket < StringIO
    def setsockopt(*args); end
  end

  before do
    allow(TCPSocket).to receive(:open).and_return(FakeSocket.new)
  end

  def stub_request(fake_response, &block)
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
end
