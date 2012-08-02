require 'raven/interfaces'

module Raven

  class MessageInterface < Interface

    name 'sentry.interfaces.Message'
    property :message, :required => true
    property :params

    def initialize(*arguments)
      self.params = []
      super(*arguments)
    end
  end

  register_interface :message => MessageInterface

end
