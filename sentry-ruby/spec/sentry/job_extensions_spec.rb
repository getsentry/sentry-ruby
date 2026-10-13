# frozen_string_literal: true

RSpec.describe "Sentry job extensions" do
  let(:extension_class) do
    Class.new(Sentry::JobExtensions::Extension) do
      def initialize(name:, claim_check:)
        super(name: name)
        @claim_check = claim_check
      end

      def handles?(job)
        @claim_check.call(job)
      end
    end
  end

  let(:sidekiq_job) { double("job", adapter: "sidekiq") }
  let(:good_job_job) { double("job", adapter: "good_job") }

  def build_extension(name, claims: ->(job) { job.adapter == name })
    extension_class.new(name: name, claim_check: claims)
  end

  after { Sentry.job_extensions.clear }

  describe ".register_job_extension" do
    it "makes an extension available before Sentry is initialized" do
      extension = build_extension("sidekiq")

      Sentry.register_job_extension(extension)

      expect(Sentry.initialized?).to eq(false)
      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
    end

    it "makes an extension available after Sentry is initialized" do
      perform_basic_setup
      extension = build_extension("sidekiq")

      Sentry.register_job_extension(extension)

      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
    end

    it "keeps registrations across Sentry re-initialization" do
      extension = build_extension("sidekiq")
      Sentry.register_job_extension(extension)

      perform_basic_setup

      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
    end

    it "rejects an extension whose name is already registered and keeps the original" do
      original = build_extension("sidekiq")
      Sentry.register_job_extension(original)

      expect { Sentry.register_job_extension(build_extension("sidekiq")) }
        .to raise_error(ArgumentError, /sidekiq/)
      expect(Sentry.job_extensions.for(sidekiq_job)).to be(original)
    end

    it "rejects an object that is not an extension instance and keeps existing registrations" do
      extension = build_extension("sidekiq")
      Sentry.register_job_extension(extension)
      duck = double("duck", name: "good_job", handles?: true)

      expect { Sentry.register_job_extension(duck) }.to raise_error(ArgumentError)
      expect { Sentry.register_job_extension(extension_class) }.to raise_error(ArgumentError)
      expect(Sentry.job_extensions.for(sidekiq_job)).to be(extension)
      expect(Sentry.job_extensions.for(good_job_job)).to be_nil
    end
  end

  describe "Sentry::JobExtensions::Extension" do
    it "rejects a blank name" do
      expect { build_extension("") }.to raise_error(ArgumentError)
      expect { build_extension(nil) }.to raise_error(ArgumentError)
    end

    it "does not claim any job by default" do
      Sentry.register_job_extension(Sentry::JobExtensions::Extension.new(name: "noop"))

      expect(Sentry.job_extensions.for(sidekiq_job)).to be_nil
    end
  end

  describe "#for" do
    it "returns the extension that claims the job" do
      sidekiq = build_extension("sidekiq")
      good_job = build_extension("good_job")
      Sentry.register_job_extension(sidekiq)
      Sentry.register_job_extension(good_job)

      expect(Sentry.job_extensions.for(good_job_job)).to be(good_job)
    end

    it "returns nil when no extension claims the job" do
      Sentry.register_job_extension(build_extension("sidekiq"))

      expect(Sentry.job_extensions.for(good_job_job)).to be_nil
    end

    it "returns the earliest registered extension when several claim the job" do
      first = build_extension("first", claims: ->(_job) { true })
      second = build_extension("second", claims: ->(_job) { true })
      Sentry.register_job_extension(first)
      Sentry.register_job_extension(second)

      expect(Sentry.job_extensions.for(sidekiq_job)).to be(first)
    end

    context "when a claim check raises a StandardError" do
      let(:string_io) { StringIO.new }
      let(:broken) { build_extension("broken", claims: ->(_job) { raise "claim failed" }) }

      before do
        perform_basic_setup { |config| config.sdk_logger = Logger.new(string_io) }
      end

      it "logs the failure and considers the remaining extensions" do
        sidekiq = build_extension("sidekiq")
        Sentry.register_job_extension(broken)
        Sentry.register_job_extension(sidekiq)

        expect(Sentry.job_extensions.for(sidekiq_job)).to be(sidekiq)
        expect(string_io.string).to include("broken", "claim failed")
      end

      it "returns nil when no other extension claims the job" do
        Sentry.register_job_extension(broken)

        expect(Sentry.job_extensions.for(sidekiq_job)).to be_nil
      end
    end

    it "treats a raising claim check as not claiming when Sentry is not initialized" do
      Sentry.register_job_extension(build_extension("broken", claims: ->(_job) { raise "claim failed" }))

      expect(Sentry.job_extensions.for(sidekiq_job)).to be_nil
    end

    it "propagates exceptions outside StandardError from a claim check" do
      Sentry.register_job_extension(build_extension("interrupted", claims: ->(_job) { raise Interrupt }))

      expect { Sentry.job_extensions.for(sidekiq_job) }.to raise_error(Interrupt)
    end
  end
end
