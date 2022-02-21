require 'spec_helper'
require 'contexts/with_request_mock'

RSpec.describe "rate limiting" do
  include_context "with request mock"

  before do
    perform_basic_setup
  end

  let(:configuration) do
    Sentry.configuration
  end
  let(:client) { Sentry.get_current_client }
  let(:data) do
    subject.envelope_from_event(client.event_from_message("foobarbaz").to_hash).to_s
  end

  subject { Sentry::HTTPTransport.new(configuration) }

  describe "#is_rate_limited?" do
    let(:transaction_event) do
      client.event_from_transaction(Sentry::Transaction.new)
    end

    context "with only category limits" do
      it "returns true for still limited category" do
        subject.rate_limits.merge!("error" => Time.now + 60,
                                   "transaction" => Time.now + 60,
                                   "session" => Time.now + 60)

        expect(subject.is_rate_limited?("event")).to eq(true)
        expect(subject.is_rate_limited?("transaction")).to eq(true)
        expect(subject.is_rate_limited?("sessions")).to eq(true)
      end

      it "returns false for passed limited category" do
        subject.rate_limits.merge!("error" => Time.now - 10,
                                   "transaction" => Time.now - 10,
                                   "session" => Time.now - 10)

        expect(subject.is_rate_limited?("event")).to eq(false)
        expect(subject.is_rate_limited?("transaction")).to eq(false)
        expect(subject.is_rate_limited?("sessions")).to eq(false)
      end

      it "returns false for not listed category" do
        subject.rate_limits.merge!("transaction" => Time.now + 10)

        expect(subject.is_rate_limited?("event")).to eq(false)
        expect(subject.is_rate_limited?("sessions")).to eq(false)
      end
    end

    context "with only universal limits" do
      it "returns true when still limited" do
        subject.rate_limits.merge!(nil => Time.now + 60)

        expect(subject.is_rate_limited?("event")).to eq(true)
      end

      it "returns false when passed limit" do
        subject.rate_limits.merge!(nil => Time.now - 10)

        expect(subject.is_rate_limited?("event")).to eq(false)
      end
    end

    context "with both category-based and universal limits" do
      it "checks both limits and picks the greater value" do
        subject.rate_limits.merge!(
          "error" => Time.now + 60,
          nil => Time.now - 10
        )

        expect(subject.is_rate_limited?("event")).to eq(true)

        subject.rate_limits.merge!(
          "error" => Time.now - 60,
          nil => Time.now + 10
        )

        expect(subject.is_rate_limited?("event")).to eq(true)
      end
    end
  end

  describe "rate limit header processing" do
    before do
      stub_request(fake_response)
    end

    shared_examples "rate limiting headers handling" do
      context "with x-sentry-rate-limits header" do
        now = Time.now

        [
          {
            header: "", expected_limits: {}
          },
          {
            header: " ", expected_limits: {}
          },
          {
            header: " , ", expected_limits: {}
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

        context "when receiving a greater value for a present category" do
          let(:headers) do
            { "x-sentry-rate-limits" => "120:error:organization" }
          end

          before do
            subject.rate_limits.merge!("error" => now + 10)
          end

          it "overrides the current limit" do
            send_data_and_verify_response(now)
            expect(subject.rate_limits).to eq({ "error" => now + 120 })
          end
        end

        context "when receiving a smaller value for a present category" do
          let(:headers) do
            { "x-sentry-rate-limits" => "10:error:organization" }
          end

          before do
            subject.rate_limits.merge!("error" => now + 120)
          end

          it "keeps the current limit" do
            send_data_and_verify_response(now)
            expect(subject.rate_limits).to eq({ "error" => now + 120 })
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
      let(:fake_response) { build_fake_response("200", headers: headers) }

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
      let(:fake_response) { build_fake_response("429", headers: headers) }

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
