# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that respects rescue_from" do
  context "when rescue_from suppresses the error" do
    let(:rescued_job) do
      job_fixture do
        rescue_from(StandardError) { |_error| nil }

        def perform
          raise "boom from rescued_job spec"
        end
      end
    end

    it "does not capture an event" do
      expect do
        rescued_job.perform_later
        drain
      end.not_to raise_error

      expect(sentry_events).to be_empty
    end
  end

  context "when the rescue_from callback raises a new error" do
    let(:problematic_rescued_job) do
      job_fixture do
        rescue_from(StandardError) { |_error| raise "boom from rescue callback" }

        def perform
          raise "original boom from problematic_rescued_job spec"
        end
      end
    end

    it "captures one event chaining the original and callback errors" do
      expect do
        problematic_rescued_job.perform_later
        drain
      end.to raise_error(RuntimeError, /boom from rescue callback/)

      expect(sentry_events.size).to eq(1)

      messages = extract_sentry_exceptions(sentry_events.last).map(&:value)
      expect(messages).to include(match(/original boom from problematic_rescued_job spec/))
      expect(messages).to include(match(/boom from rescue callback/))
    end
  end
end
