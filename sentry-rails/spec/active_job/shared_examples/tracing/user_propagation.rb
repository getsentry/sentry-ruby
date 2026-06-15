# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that propagates Sentry user context through job payloads" do
  let(:successful_job) do
    job_fixture do
      def perform; end
    end
  end

  let(:failing_job) do
    job_fixture do
      def perform
        raise "boom from user_propagation spec"
      end
    end
  end

  let(:full_user) do
    {
      id: "u1",
      email: "alice@example.com",
      username: "alice",
      ip_address: "1.2.3.4",
      segment: "vip"
    }
  end

  context "when send_default_pii is true" do
    let(:configure_sentry) do
      proc do |config|
        config.traces_sample_rate = 1.0
        config.send_default_pii = true
      end
    end

    it "propagates only id, email, and username to the consumer transaction" do
      Sentry.set_user(full_user)

      successful_job.perform_later

      # Simulate the cross-process boundary by clearing the producer scope
      # before the consumer runs. Without this the consumer's with_scope
      # inherits the user from the test thread and the test cannot tell
      # whether propagation actually happened.
      Sentry.set_user({})

      drain

      expect(consumer_transaction).not_to be_nil
      expect(consumer_transaction.user).to eq(
        id: "u1",
        email: "alice@example.com",
        username: "alice"
      )
    end

    it "propagates the whitelisted user to a captured error event" do
      Sentry.set_user(full_user)

      failing_job.perform_later
      Sentry.set_user({})

      expect { drain }.to raise_error(RuntimeError, /boom from user_propagation spec/)

      error_event = sentry_events.find { |e| e.is_a?(Sentry::ErrorEvent) }
      expect(error_event).not_to be_nil
      expect(error_event.user).to eq(
        id: "u1",
        email: "alice@example.com",
        username: "alice"
      )
    end
  end

  context "when send_default_pii is true and logs are enabled" do
    let(:configure_sentry) do
      proc do |config|
        config.traces_sample_rate = 1.0
        config.send_default_pii = true
        config.enable_logs = true
      end
    end

    let(:logging_job) do
      job_fixture do
        def perform
          Sentry.logger.info("hello from user_propagation spec")
        end
      end
    end

    it "carries the propagated user as telemetry attributes on logs emitted inside the job" do
      Sentry.set_user(full_user)

      logging_job.perform_later
      Sentry.set_user({})

      drain
      Sentry.get_current_client.flush

      log = sentry_logs.find { |l| l[:body] == "hello from user_propagation spec" }

      expect(log).not_to be_nil
      expect(log[:attributes]["user.id"]).to eq(value: "u1", type: "string")
      expect(log[:attributes]["user.email"]).to eq(value: "alice@example.com", type: "string")
      expect(log[:attributes]["user.name"]).to eq(value: "alice", type: "string")
    end
  end

  context "when send_default_pii is false" do
    let(:configure_sentry) do
      proc do |config|
        config.traces_sample_rate = 1.0
        config.send_default_pii = false
      end
    end

    it "does not propagate user context to the consumer transaction" do
      Sentry.set_user(full_user)

      successful_job.perform_later
      Sentry.set_user({})

      drain

      expect(consumer_transaction).not_to be_nil
      expect(consumer_transaction.user).to eq({})
    end
  end
end
