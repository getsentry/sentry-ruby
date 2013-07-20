require 'rake'
require 'raven'
require 'raven/cli'

namespace :raven do
  desc "Send a test event to the remote Sentry server"
  task :test, [:dsn] => :environment do |t, args|
    Raven::CLI::test(args.dsn)
  end
end
