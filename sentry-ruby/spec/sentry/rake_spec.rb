require "spec_helper"

RSpec.describe "rake auto-reporting" do
  it "sends a report to Sentry" do
    message = ""

    # if we change the directory in the current process, it'll affect other tests that relies on system call too
    # e.g. release detection tests
    Thread.new do
      message = `cd spec/support && bundle exec rake raise_exception 2>&1`
    end.join

    expect(message).to match(/Sending envelope \[event\] [abcdef0-9]+ to Sentry/)
  end

  it "skip sending report to Sentry when skip_rake_integration = true" do
    message = ""

    # if we change the directory in the current process, it'll affect other tests that relies on system call too
    # e.g. release detection tests
    Thread.new do
      message = `cd spec/support && bundle exec rake raise_exception_without_rake_integration 2>&1`
    end.join

    expect(message).not_to match(/Sentry/)
  end
end
