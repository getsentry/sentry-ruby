require 'raven'

require 'coveralls'
Coveralls.wear!

RSpec.configure do |config|
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
end

def build_exception
  1 / 0
rescue ZeroDivisionError => exception
  return exception
end
