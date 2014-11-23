require 'rubygems'
require 'socket'
require 'securerandom'

require 'raven/error'
require 'raven/linecache'

module Raven

  class Event

    LOG_LEVELS = {
      "debug" => 10,
      "info" => 20,
      "warn" => 30,
      "warning" => 30,
      "error" => 40,
      "fatal" => 50,
    }

    BACKTRACE_RE = /^(.+?):(\d+)(?::in `(.+?)')?$/

    PLATFORM = "ruby"

    attr_reader :id
    attr_accessor :project, :message, :timestamp, :time_spent, :level
    attr_accessor :logger, :culprit, :server_name, :modules, :extra, :tags

    def initialize(options = {}, &block)
      @configuration = options[:configuration] || Raven.configuration
      @interfaces = {}

      context = options[:context] || Raven.context

      @id = options[:id] || generate_event_id
      @message = options[:message]
      @timestamp = options[:timestamp] || Time.now.utc
      @time_spent = options[:time_spent]

      @level = options[:level] || :error
      @logger = options[:logger] || 'root'
      @culprit = options[:culprit]
      @server_name = options[:server_name] || @configuration.server_name || get_hostname

      options[:modules] ||= get_modules if @configuration.send_modules

      @modules = options[:modules]

      @user = options[:user] || {}
      @user.merge!(context.user)

      @extra = options[:extra] || {}
      @extra.merge!(context.extra)

      @tags = {}
      @tags.merge!(@configuration.tags)
      @tags.merge!(options[:tags] || {})
      @tags.merge!(context.tags)

      block.call(self) if block

      if @configuration.send_in_current_environment?
        if !self[:http] && context.rack_env
          self.interface :http do |int|
            int.from_rack(context.rack_env)
          end
        end
      end

      # Some type coercion
      @timestamp = @timestamp.strftime('%Y-%m-%dT%H:%M:%S') if @timestamp.is_a?(Time)
      @time_spent = (@time_spent*1000).to_i if @time_spent.is_a?(Float)
      @level = LOG_LEVELS[@level.to_s.downcase] if @level.is_a?(String) || @level.is_a?(Symbol)
    end

    def get_hostname
      # Try to resolve the hostname to an FQDN, but fall back to whatever the load name is
      hostname = Socket.gethostname
      Socket.gethostbyname(hostname).first rescue hostname
    end

    def get_modules
      # Older versions of Rubygems don't support iterating over all specs
      Hash[Gem::Specification.map { |spec| [spec.name, spec.version.to_s] }] if Gem::Specification.respond_to?(:map)
    end

    def interface(name, value = nil, &block)
      int = Raven.find_interface(name)
      raise Error.new("Unknown interface: #{name}") unless int
      @interfaces[int.name] = int.new(value, &block) if value || block
      @interfaces[int.name]
    end

    def [](key)
      interface(key)
    end

    def []=(key, value)
      interface(key, value)
    end

    def to_hash
      data = {
        'event_id' => @id,
        'message' => @message,
        'timestamp' => @timestamp,
        'time_spent' => @time_spent,
        'level' => @level,
        'project' => @project,
        'logger' => @logger,
        'platform' => PLATFORM,
      }
      data['culprit'] = @culprit if @culprit
      data['server_name'] = @server_name if @server_name
      data['modules'] = @modules if @modules
      data['extra'] = @extra if @extra
      data['tags'] = @tags if @tags
      data['user'] = @user if @user
      @interfaces.each_pair do |name, int_data|
        data[name] = int_data.to_hash
      end
      data
    end

    def self.from_exception(exc, options = {}, &block)
      notes = exc.instance_variable_get(:@__raven_context) || {}
      options = notes.merge(options)

      configuration = options[:configuration] || Raven.configuration
      if exc.is_a?(Raven::Error)
        # Try to prevent error reporting loops
        Raven.logger.info "Refusing to capture Raven error: #{exc.inspect}"
        return nil
      end
      if configuration[:excluded_exceptions].any? { |x| (x === exc rescue false) || x == exc.class.name }
        Raven.logger.info "User excluded error: #{exc.inspect}"
        return nil
      end

      context_lines = configuration[:context_lines]

      new(options) do |evt|
        evt.message = "#{exc.class}: #{exc.message}"
        evt.level = options[:level] || :error

        evt.interface(:exception) do |int|
          int.type = exc.class.to_s
          int.value = exc.to_s
          int.module = exc.class.to_s.split('::')[0...-1].join('::')

          # TODO(dcramer): this needs cleaned up, but I couldn't figure out how to
          # work Hashie as a non-Rubyist
          if exc.backtrace
            int.stacktrace = StacktraceInterface.new do |stacktrace|
              backtrace = Backtrace.parse(exc.backtrace)
              stacktrace.frames = backtrace.lines.reverse.map do |line|
                stacktrace.frame do |frame|
                  frame.abs_path = line.file
                  frame.function = line.method
                  frame.lineno = line.number
                  frame.in_app = line.in_app
                  if context_lines && frame.abs_path
                    frame.pre_context, frame.context_line, frame.post_context = \
                      evt.get_file_context(frame.abs_path, frame.lineno, context_lines)
                  end
                end
              end.select { |f| f.filename }

              evt.culprit = evt.get_culprit(stacktrace.frames)
            end
          end
        end

        block.call(evt) if block
      end
    end

    def self.from_message(message, options = {})
      new(options) do |evt|
        evt.message = message
        evt.level = options[:level] || :error
        evt.interface :message do |int|
          int.message = message
        end
      end
    end

    # Because linecache can go to hell
    def self._source_lines(path, from, to)
    end

    def get_file_context(filename, lineno, context)
      lines = (2 * context + 1).times.map do |i|
        Raven::LineCache.getline(filename, lineno - context + i)
      end
      [lines[0..(context - 1)], lines[context], lines[(context + 1)..-1]]
    end

    def get_culprit(frames)
      lastframe = frames.reverse.find { |f| f.in_app } || frames.last
      "#{lastframe.filename} in #{lastframe.function} at line #{lastframe.lineno}" if lastframe
    end

    # For cross-language compat
    class << self
      alias :captureException :from_exception
      alias :captureMessage :from_message
      alias :capture_exception :from_exception
      alias :capture_message :from_message
    end

    private

    def generate_event_id
      # generate a uuid. copy-pasted from SecureRandom, this method is not
      # available in <1.9.
      ary = SecureRandom.random_bytes(16).unpack("NnnnnN")
      ary[2] = (ary[2] & 0x0fff) | 0x4000
      ary[3] = (ary[3] & 0x3fff) | 0x8000
      uuid = "%08x-%04x-%04x-%04x-%04x%08x" % ary
      Digest::MD5.hexdigest(uuid)
    end
  end
end
