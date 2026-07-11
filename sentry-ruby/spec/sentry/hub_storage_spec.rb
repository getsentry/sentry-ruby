# frozen_string_literal: true

RSpec.describe Sentry::HubStorage do
  around do |example|
    original = described_class.isolation_level
    example.run
  ensure
    described_class.isolation_level = original
    described_class.clear
  end

  describe ".isolation_level=" do
    it "defaults to :thread" do
      # the module sets :thread on load
      described_class.isolation_level = :thread
      expect(described_class.isolation_level).to eq(:thread)
    end

    it "accepts :fiber" do
      described_class.isolation_level = :fiber
      expect(described_class.isolation_level).to eq(:fiber)
    end

    it "raises ArgumentError for an unknown level" do
      expect { described_class.isolation_level = :process }
        .to raise_error(ArgumentError, /isolation_level must be one of/)
    end
  end

  describe ".fiber_storage_available?", when: { fiber_storage?: [] } do
    it "is true on Ruby 3.2+" do
      expect(described_class.fiber_storage_available?).to be(true)
    end
  end

  describe ".get / .set / .clear" do
    let(:hub) { instance_double(Sentry::Hub) }

    context "with :thread isolation" do
      before { described_class.isolation_level = :thread }

      it "stores and reads the hub from thread-local storage" do
        described_class.set(hub)
        expect(described_class.get).to eq(hub)
        expect(Thread.current.thread_variable_get(Sentry::THREAD_LOCAL)).to eq(hub)
      end

      it "clears the hub" do
        described_class.set(hub)
        described_class.clear
        expect(described_class.get).to be_nil
      end

      it "isolates the hub per thread" do
        described_class.set(hub)
        other = Thread.new { described_class.get }.value
        expect(other).to be_nil
      end
    end

    context "with :fiber isolation", when: { fiber_storage?: [] } do
      before { described_class.isolation_level = :fiber }

      it "stores and reads the hub from fiber storage" do
        described_class.set(hub)
        expect(described_class.get).to eq(hub)
        expect(Fiber[Sentry::THREAD_LOCAL]).to eq(hub)
      end

      it "clears the hub" do
        described_class.set(hub)
        described_class.clear
        expect(described_class.get).to be_nil
      end

      it "isolates the hub between sibling fibers" do
        described_class.set(hub)

        sibling = Fiber.new do
          described_class.set(:sibling_hub)
          described_class.get
        end

        expect(sibling.resume).to eq(:sibling_hub)
        # the sibling's write must not leak back into the current fiber
        expect(described_class.get).to eq(hub)
      end

      it "lets a child fiber inherit the parent's hub (the #1374 case)" do
        described_class.set(hub)
        child = Fiber.new { described_class.get }
        expect(child.resume).to eq(hub)
      end
    end
  end
end
