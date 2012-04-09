require 'hashie'

require 'raven/interfaces'

module Raven

  class StacktraceInterface < Interface

    name 'sentry.interfaces.Stacktrace'
    property :frames, :default => []

    def to_hash
      data = super
      data['frames'] = data['frames'].map{|frame| frame.to_hash}
      data
    end

    def frame(attributes=nil, &block)
      Frame.new(attributes, &block)
    end

    # Not actually an interface, but I want to use the same style
    class Frame < Interface
      property :abs_path
      property :filename, :required => true
      property :function
      property :vars, :default => {}
      property :pre_context, :default => []
      property :post_context, :default => []
      property :context_line
      property :lineno, :required => true

      def to_hash
        data = super
        data.delete('vars') unless self.vars
        data
      end
    end

  end

  register_interface :stack_trace => StacktraceInterface

end
