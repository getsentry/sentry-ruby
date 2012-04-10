require 'raven/interfaces'

module Raven

  class ExceptionInterface < Interface

    name 'sentry.interfaces.Exception'
    property :type, :required => true
    property :value, :required => true
    property :module

  end

  register_interface :exception => ExceptionInterface

end
