require 'spec_helper'

describe 'Rake tasks' do
  it 'should bundle a CLI task which captures exceptions' do
    expect(Raven::CLI.test("dummy://12345:67890@sentry.localdomain:3000/sentry/42")).to be true
  end

  it "should capture exceptions in Rake tasks" do
    expect(`cd spec/support && bundle exec rake raise_exception 2>&1`).to match(/Sending event/)
  end
end
