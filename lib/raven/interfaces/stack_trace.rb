require 'hashie'

require 'raven/interfaces'

module Raven

  class StacktraceInterface < Interface

    name 'sentry.interfaces.Stacktrace'
    property :frames, :default => []

    def initialize(*arguments)
      self.frames = []
      super(*arguments)
    end

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
      property :vars
      property :pre_context
      property :post_context
      property :context_line
      property :lineno, :required => true

      def initialize(*arguments)
        self.vars= {}
        self.pre_context = []
        self.post_context = []
        super(*arguments)
      end

      def to_hash
        data = super
        data.delete('vars') unless self.vars && !self.vars.empty?
        data.delete('pre_context') unless self.pre_context && !self.pre_context.empty?
        data.delete('post_context') unless self.post_context && !self.post_context.empty?
        data.delete('context_line') unless self.context_line && !self.context_line.empty?
        data
      end
    end

  end

  register_interface :stack_trace => StacktraceInterface

end
