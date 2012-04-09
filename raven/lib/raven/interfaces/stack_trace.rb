require 'raven/interfaces'

module Raven

  class StacktraceInterface < Interface

    name 'sentry.interfaces.Stacktrace'
    property :frames, :default => []

  end

  register_interface :stack_trace => StacktraceInterface

end
