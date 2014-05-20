require 'hashie'

require 'raven/interfaces'

module Raven
  class StacktraceInterface < Interface

    name 'stacktrace'
    property :frames, :default => []

    def initialize(*arguments)
      self.frames = []
      super(*arguments)
    end

    def to_hash(*args)
      data = super(*args)
      data['frames'] = data['frames'].map { |frame| frame.to_hash }
      data
    end

    def frame(attributes = nil, &block)
      Frame.new(attributes, &block)
    end

    # Not actually an interface, but I want to use the same style
    class Frame < Interface
      property :abs_path
      property :function
      property :vars
      property :pre_context
      property :post_context
      property :context_line
      property :lineno, :required => true
      property :in_app

      def initialize(*arguments)
        self.vars = {}
        self.pre_context = []
        self.post_context = []
        super(*arguments)
      end

      def filename
        return nil if self.abs_path.nil?

        prefix = $LOAD_PATH.select { |s| self.abs_path.start_with?(s.to_s) }.sort_by { |s| s.to_s.length }.last
        prefix ? self.abs_path[prefix.to_s.chomp(File::SEPARATOR).length+1..-1] : self.abs_path
      end

      def to_hash(*args)
        data = super(*args)
        data['filename'] = self.filename
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
