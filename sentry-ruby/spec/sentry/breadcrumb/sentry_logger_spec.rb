require "spec_helper"

RSpec.describe "Sentry::Breadcrumbs::SentryLogger" do
  before do
    Sentry.init do |config|
      config.dsn = DUMMY_DSN
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
end
