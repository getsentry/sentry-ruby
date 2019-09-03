require 'spec_helper'

RSpec.describe Raven::Logger do
  it "should log to a given IO" do
    stringio = StringIO.new
    log = Raven::Logger.new(stringio)

    log.fatal("Oh noes!")

    expect(stringio.string).to end_with("FATAL -- sentry: ** [Raven] Oh noes!\n")
  end

  it "should allow exceptions to be logged" do
    stringio = StringIO.new
    log = Raven::Logger.new(stringio)

    log.fatal(Exception.new("Oh exceptions"))

    expect(stringio.string).to end_with("FATAL -- sentry: ** [Raven] Oh exceptions\n")
  end
end
