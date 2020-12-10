require 'spec_helper'

RSpec.describe 'Rake tasks' do
  it "should capture exceptions in Rake tasks" do
    expect(`cd spec/support && bundle exec rake raise_exception 2>&1`).to match(/Sending event [abcdef0-9]+ to Sentry/)
  end
end
