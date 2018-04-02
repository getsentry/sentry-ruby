require 'test_helper'

class RavenLoggerTest < Raven::Test
  it "should log to a given IO" do
    stringio = StringIO.new
    log = Raven::Logger.new(Logger.new(stringio))

    log.fatal("Oh noes!")

    assert stringio.string.end_with? "FATAL -- sentry: ** [Raven] Oh noes!\n"
  end
end
