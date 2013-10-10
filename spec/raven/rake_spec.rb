require File::expand_path('../../spec_helper', __FILE__)
require 'raven'

describe "Catching exceptions in rake tasks" do
  rake_file = File::expand_path('../../support/Rakefile', __FILE__)

  example "intervenes when an error is raised" do
    output = run_rake_task("raven_raise")

    output[:stderr].should include('[raven] error caught')
  end

  example "does not intervene when no error is raised" do
    output = run_rake_task("raven_no_raise")

    output[:stderr].should_not include('[raven] error caught')
  end
end
