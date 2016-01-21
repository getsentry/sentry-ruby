require 'raven/interfaces'

module Raven
  class ExceptionInterface < Interface
    name 'exception'
    attr_accessor :values

    def to_hash(*args)
      data = super(*args)
      data[:values] = data[:values].map(&:to_hash) if data[:values]
      data
    end
  end

  register_interface :exception => ExceptionInterface
end
