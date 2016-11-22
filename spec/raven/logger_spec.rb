require 'spec_helper'

describe Raven::Logger do
  it "should log to a given IO" do
    stringio = StringIO.new
    log = Raven::Logger.new(stringio)

    log.fatal("Oh noes!")

    expect(stringio.string).to end_with("FATAL -- sentry: ** [Raven] Oh noes!\n")
  end
end
