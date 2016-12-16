ENV['RACK_ENV'] = ENV['RAILS_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/hell'
require 'minitest/pride'
require 'sentry-raven-without-integrations'
