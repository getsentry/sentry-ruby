require 'raven/interfaces'

module Raven
  class ExceptionInterface < Interface

    name 'exception'
    property :type, :required => true
    property :value, :required => true
    property :module
    property :stacktrace

    def to_hash(*args)
      data = super(*args)
      if data['stacktrace']
        data['stacktrace'] = data['stacktrace'].to_hash
      end
      data
    end
  end

  register_interface :exception => ExceptionInterface
end
