require 'raven/interfaces'

module Raven

  class MessageInterface < Interface

    name 'sentry.interfaces.Message'
    property :message, :required => true
    property :params, :default => []

  end

  register_interface :message => MessageInterface

end
