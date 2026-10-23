# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sentry + ActiveJob on the test adapter", type: :job do
  include_context "active_job backend harness", adapter: :test
  include_context "test adapter"

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"

  context "when the job data cannot be encoded as JSON" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }
    let(:unencodable_argument) { "\xFF".dup.force_encoding(Encoding::UTF_8) }

    it "enqueues and performs the job and omits messaging.message.body.size" do
      performed_arguments = []
      recording_job = job_fixture do
        define_method(:perform) { |argument| performed_arguments << argument }
      end

      within_parent_transaction { recording_job.perform_later(unencodable_argument) }
      drain

      publish_span = transactions.flat_map(&:spans).find { |s| s[:op] == "queue.publish" }
      consumer_data = consumer_transaction.contexts.dig(:trace, :data)
      expect(performed_arguments).to eq([unencodable_argument])
      expect(publish_span[:data]).to include("messaging.destination.name" => "default")
      expect(publish_span[:data]).not_to have_key("messaging.message.body.size")
      expect(consumer_data).to include("messaging.destination.name" => "default")
      expect(consumer_data).not_to have_key("messaging.message.body.size")
    end
  end
end
