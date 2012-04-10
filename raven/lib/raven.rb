require 'raven/client'
require 'raven/event'
require 'raven/interfaces/message'
require 'raven/interfaces/exception'
require 'raven/interfaces/stack_trace'

module Raven
  def self.e
    raise Error.new('Test error')
  rescue Error => exc
    exc
  end
end
