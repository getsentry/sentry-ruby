require 'spec_helper'

RSpec.describe "rate limiting" do
  let(:configuration) do
    Sentry::Configuration.new.tap do |config|
      config.dsn = 'http://12345@sentry.localdomain/sentry/42'
    end
  end
  let(:client) { Sentry::Client.new(configuration) }
  let(:event) { client.event_from_message("foobarbaz") }
  let(:data) do
    subject.encode(event.to_hash)
  end

  subject { Sentry::HTTPTransport.new(configuration) }

  describe "#is_rate_limited?" do
    let(:transaction_event) do
      client.event_from_transaction(Sentry::Transaction.new)
    end

    context "with only category limits" do
      it "returns true for still limited category" do
        subject.rate_limits.merge!("error" => Time.now + 60)

        expect(subject.is_rate_limited?(event.to_hash)).to eq(true)
      end

      it "returns false for passed limited category" do
        subject.rate_limits.merge!("error" => Time.now - 10)

        expect(subject.is_rate_limited?(event.to_hash)).to eq(false)
      end

      it "returns false for not listed category" do
        subject.rate_limits.merge!("transaction" => Time.now + 10)

        expect(subject.is_rate_limited?(event.to_hash)).to eq(false)
      end
    end

    context "with only universal limits" do
      it "returns true when still limited" do
        subject.rate_limits.merge!(nil => Time.now + 60)

        expect(subject.is_rate_limited?(event.to_hash)).to eq(true)
      end

      it "returns false when passed limit" do
        subject.rate_limits.merge!(nil => Time.now - 10)

        expect(subject.is_rate_limited?(event.to_hash)).to eq(false)
      end
    end

    context "with both category-based and universal limits" do
      it "prioritizes category limits" do
        subject.rate_limits.merge!(
          "error" => Time.now + 60,
          nil => Time.now - 10
        )

        expect(subject.is_rate_limited?(event.to_hash)).to eq(true)
      end
    end
  end

  describe "rate limit header processing" do
    before do
      configuration.transport.http_adapter = [:test, stubs]
    end

    shared_examples "rate limiting headers handling" do
      context "with x-sentry-rate-limits header" do
        now = Time.now

        [
          {
            header: "", expected_limits: {}
          },
          {
            header: "invalid", expected_limits: {}
          },
          {
            header: ",,foo,", expected_limits: {}
          },
          {
            header: "42::organization, invalid, 4711:foobar;transaction;security:project",
            expected_limits: {
              nil => now + 42,
              "transaction" => now + 4711,
              "foobar" => now + 4711, "security" => now + 4711
            }
          }
        ].each do |pair|
          context "with header value: '#{pair[:header]}'" do
            let(:headers) do
              { "x-sentry-rate-limits" => pair[:header] }
            end

            it "parses the header into correct limits" do
              send_data_and_verify_response(now)
              expect(subject.rate_limits).to eq(pair[:expected_limits])
            end
          end
        end
      end

      context "with retry-after header" do
        now = Time.now

        [
          {
            header: "48", expected_limits: { nil => now + 48 }
          },
          {
            header: "invalid", expected_limits: { nil => now + 60}
          },
          {
            header: "", expected_limits: { nil => now + 60}
          },
        ].each do |pair|
          context "with header value: '#{pair[:header]}'" do
            let(:headers) do
              { "retry-after" => pair[:header] }
            end

            it "parses the header into correct limits" do
              send_data_and_verify_response(now)
              expect(subject.rate_limits).to eq(pair[:expected_limits])
            end
          end
        end
      end

      context "with both x-sentry-rate-limits and retry-after headers" do
        let(:headers) do
          { "x-sentry-rate-limits" => "42:error:organization", "retry-after" => "42" }
        end

        it "parses x-sentry-rate-limits first" do
          now = Time.now

          send_data_and_verify_response(now)
          expect(subject.rate_limits).to eq({ "error" => now + 42 })
        end
      end
    end

    context "received 200 response" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') do
            [
              200, headers, ""
            ]
          end
        end
      end

      it_behaves_like "rate limiting headers handling" do
        def send_data_and_verify_response(time)
          Timecop.freeze(time) do
            subject.send_data(data)
          end
        end
      end

      context "with no rate limiting headers" do
        let(:headers) do
          {}
        end

        it "doesn't add any rate limites" do
          now = Time.now

          Timecop.freeze(now) do
            subject.send_data(data)
          end
          expect(subject.rate_limits).to eq({})
        end
      end
    end

    context "received 429 response" do
      let(:stubs) do
        Faraday::Adapter::Test::Stubs.new do |stub|
          stub.post('sentry/api/42/envelope/') do
            [
              429, headers, "{\"detail\":\"event rejected due to rate limit\"}"
            ]
          end
        end
      end

      it_behaves_like "rate limiting headers handling" do
        def send_data_and_verify_response(time)
          Timecop.freeze(time) do
            expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 429/)
          end
        end
      end

      context "with no rate limiting headers" do
        let(:headers) do
          {}
        end

        it "adds default limits" do
          now = Time.now

          Timecop.freeze(now) do
            expect { subject.send_data(data) }.to raise_error(Sentry::ExternalError, /the server responded with status 429/)
          end
          expect(subject.rate_limits).to eq({ nil => now + 60 })
        end
      end
    end
  end
end
