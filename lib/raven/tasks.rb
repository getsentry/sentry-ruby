require 'rake'
require 'raven'
require 'raven/cli'

namespace :raven do
  desc "Send a test event to the remote Sentry server"
  task :test, [:dsn] do |t, args|
    if defined? Rails
      Rake::Task["environment"].invoke
    end
    Raven::CLI::test(args.dsn)
  end
end
