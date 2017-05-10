ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/hell'
require 'minitest/pride'
require 'sentry-raven-without-integrations'

class Minitest::Spec
  def build_exception
    1 / 0
  rescue ZeroDivisionError => exception
    return exception
  end
end
