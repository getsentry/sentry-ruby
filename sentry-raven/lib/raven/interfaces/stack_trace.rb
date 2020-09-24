module Raven
  class StacktraceInterface < Interface
    attr_accessor :frames

    def initialize(*arguments)
      super(*arguments)
    end

    def self.sentry_alias
      :stacktrace
    end

    def to_hash(*args)
      data = super(*args)
      data[:frames] = data[:frames].map(&:to_hash)
      data
    end

    # Not actually an interface, but I want to use the same style
    class Frame < Interface
      attr_accessor :abs_path, :context_line, :function, :in_app,
                    :lineno, :module, :pre_context, :post_context, :vars

      def initialize(*arguments)
        super(*arguments)
      end

      def filename
        return if abs_path.nil?
        return @filename if instance_variable_defined?(:@filename)

        prefix =
          if under_project_root? && in_app
            project_root
          elsif under_project_root?
            longest_load_path || project_root
          else
            longest_load_path
          end

        @filename = prefix ? abs_path[prefix.to_s.chomp(File::SEPARATOR).length + 1..-1] : abs_path
      end

      def to_hash(*args)
        data = super(*args)
        data[:filename] = filename
        data.delete(:vars) unless vars && !vars.empty?
        data.delete(:pre_context) unless pre_context && !pre_context.empty?
        data.delete(:post_context) unless post_context && !post_context.empty?
        data.delete(:context_line) unless context_line && !context_line.empty?
        data
      end

      private

      def under_project_root?
        project_root && abs_path.start_with?(project_root)
      end

      def project_root
        @project_root ||= Raven.configuration.project_root&.to_s
      end

      def longest_load_path
        $LOAD_PATH.select { |path| abs_path.start_with?(path.to_s) }.max_by(&:size)
      end
    end
  end
end
