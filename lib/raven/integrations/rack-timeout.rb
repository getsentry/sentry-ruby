# We need to do this because of the way integration loading works
require "rack/timeout/base"

# This integration is a good example of how to change how exceptions
# get grouped by Sentry's UI. Simply override #raven_context in
# the exception class, and append something to the fingerprint
# that will distinguish exceptions in the way you desire.
module RackTimeoutExtensions
  def raven_context
    { :fingerprint => ["{{ default }}", env["REQUEST_URI"]] }
  end
end

Rack::Timeout::Error.include RackTimeoutExtensions
Rack::Timeout::RequestTimeoutException.include RackTimeoutExtensions
