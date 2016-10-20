require 'spec_helper'

describe 'Rake tasks' do
  it 'should bundle a CLI task which captures exceptions' do
    expect(Raven::CLI.test("dummy://notaserver:notapass@notathing/12345")).to be true
  end

  it "should capture exceptions in Rake tasks" do
    Raven.configure do |config|
      config.dsn = "dummy://notaserver:notapass@notathing/12345"
    end
    expect(`cd spec/support && bundle exec rake raise_exception 2>&1`).to match(/Sending event/)
  end
end
