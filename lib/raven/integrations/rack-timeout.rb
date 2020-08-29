# We need to do this because of the way integration loading works
require "rack/timeout/base" unless defined?(Rack::Timeout)

# This integration is a good example of how to change how exceptions
# get grouped by Sentry's UI. Simply override #raven_context in
# the exception class, and append something to the fingerprint
# that will distinguish exceptions in the way you desire.
module RackTimeoutExtensions
  def raven_context
    # Only rack-timeout 0.3.0+ provides the request environment, but we can't
    # gate this based on a gem version constant because rack-timeout does
    # not provide one.
    if defined?(env)
      { :fingerprint => ["{{ default }}", env["REQUEST_URI"]] }
    else
      {}
    end
  end
end

Rack::Timeout::Error.include(RackTimeoutExtensions)
Rack::Timeout::RequestTimeoutException.include(RackTimeoutExtensions)
