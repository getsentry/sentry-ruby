require 'raven/interfaces'

module Raven

  class MessageInterface < Interface

    name 'sentry.interfaces.Message'
    property :message, :required => true
    property :params

    def initialize(attributes)
      self.params = []
      super(attributes)
    end
  end

  register_interface :message => MessageInterface

end
