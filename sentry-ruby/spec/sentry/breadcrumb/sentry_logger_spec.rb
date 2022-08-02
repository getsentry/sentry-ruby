require "spec_helper"

RSpec.describe "Sentry::Breadcrumbs::SentryLogger" do
  before do
    perform_basic_setup do |config|
      config.breadcrumbs_logger = [:sentry_logger]
    end
  end

  let(:logger) { ::Logger.new(nil) }
  let(:breadcrumbs) { Sentry.get_current_scope.breadcrumbs }

  it "records the breadcrumb when logger is called" do
    logger.info("foo")

    breadcrumb = breadcrumbs.peek

    expect(breadcrumb.level).to eq("info")
    expect(breadcrumb.message).to eq("foo")
  end

  it "records non-String message" do
    logger.info(200)
    expect(breadcrumbs.peek.message).to eq("200")
  end

  it "does not affect the return of the logger call" do
    expect(logger.info("foo")).to be_nil
  end

  it "ignores traces with #{Sentry::LOGGER_PROGNAME}" do
    logger.info(Sentry::LOGGER_PROGNAME) { "foo" }

    expect(breadcrumbs.peek).to be_nil
  end

  it "passes severity as a hint" do
    hint = nil
    Sentry.configuration.before_breadcrumb = lambda do |breadcrumb, h|
      hint = h
      breadcrumb
    end

    logger.info("foo")

    expect(breadcrumbs.peek.message).to eq("foo")
    expect(hint[:severity]).to eq(1)
  end

  describe "category assignment" do
    it "assigned 'logger' by default" do
      logger.info("foo")

      expect(breadcrumbs.peek.category).to eq("logger")
    end

    it "assigns progname if provided" do
      logger.info("test category") { "foo" }

      expect(breadcrumbs.peek.category).to eq("test category")
    end
  end

  describe "when closed" do
    it "noops" do
      Sentry.close
      expect(Sentry).not_to receive(:add_breadcrumb)
      logger.info("foo")
    end

    # see https://github.com/getsentry/sentry-ruby/issues/1858
    it "noops on thread with cloned hub" do
      mutex = Mutex.new
      cv = ConditionVariable.new

      a = Thread.new do
        expect(Sentry.get_current_hub).to be_a(Sentry::Hub)

        # close in another thread
        b = Thread.new do
          mutex.synchronize do
            Sentry.close
            cv.signal
          end
        end

        mutex.synchronize do
          # wait for other thread to close SDK
          cv.wait(mutex)

          expect(Sentry).not_to receive(:add_breadcrumb)
          logger.info("foo")
        end

        b.join
      end

      a.join
    end
  end
end
