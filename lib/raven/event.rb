require 'rubygems'
require 'socket'
require 'uuidtools'

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
    }

    BACKTRACE_RE = /^(.+?):(\d+)(?::in `(.+?)')?$/

    attr_reader :id
    attr_accessor :project, :message, :timestamp, :level
    attr_accessor :logger, :culprit, :server_name, :modules, :extra

    def initialize(options={}, configuration=nil, &block)
      @configuration = configuration || Raven.configuration
      @interfaces = {}

      @id = options[:id] || UUIDTools::UUID.random_create.hexdigest
      @message = options[:message]
      @timestamp = options[:timestamp] || Time.now.utc
      @level = options[:level] || :error
      @logger = options[:logger] || 'root'
      @culprit = options[:culprit]
      @extra = options[:extra]

      # Try to resolve the hostname to an FQDN, but fall back to whatever the load name is
      hostname = Socket.gethostname
      hostname = Socket.gethostbyname(hostname).first rescue hostname
      @server_name = options[:server_name] || hostname

      # Older versions of Rubygems don't support iterating over all specs
      if @configuration.send_modules && Gem::Specification.respond_to?(:map)
        options[:modules] ||= Hash[Gem::Specification.map {|spec| [spec.name, spec.version.to_s]}]
      end
      @modules = options[:modules]

      block.call(self) if block

      # Some type coercion
      @timestamp = @timestamp.strftime('%Y-%m-%dT%H:%M:%S') if @timestamp.is_a?(Time)
      @level = LOG_LEVELS[@level.to_s.downcase] if @level.is_a?(String) || @level.is_a?(Symbol)

      # Basic sanity checking
      raise Error.new('A message is required for all events') unless @message && !@message.empty?
      raise Error.new('A timestamp is required for all events') unless @timestamp
    end

    def interface(name, value=nil, &block)
      int = Raven::find_interface(name)
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
        'event_id' => self.id,
        'message' => self.message,
        'timestamp' => self.timestamp,
        'level' => self.level,
        'project' => self.project,
        'logger' => self.logger,
      }
      data['culprit'] = self.culprit if self.culprit
      data['server_name'] = self.server_name if self.server_name
      data['modules'] = self.modules if self.modules
      data['extra'] = self.extra if self.extra
      @interfaces.each_pair do |name, int_data|
        data[name] = int_data.to_hash
      end
      data
    end

    def self.capture_exception(exc, configuration=nil, &block)
      configuration ||= Raven.configuration
      if exc.is_a?(Raven::Error)
        # Try to prevent error reporting loops
        Raven.logger.info "Refusing to capture Raven error: #{exc.inspect}"
        return nil
      end
      if configuration[:excluded_exceptions].include? exc.class.name
        Raven.logger.info "User excluded error: #{exc.inspect}"
        return nil
      end
      self.new({}, configuration) do |evt|
        evt.message = "#{exc.class.to_s}: #{exc.message}"
        evt.level = :error
        evt.parse_exception(exc)
        if (exc.backtrace)
          evt.interface :stack_trace do |int|
            int.frames = exc.backtrace.reverse.map do |trace_line|
              int.frame {|frame| evt.parse_backtrace_line(trace_line, frame) }
            end
            evt.culprit = evt.get_culprit(int.frames)
          end
        end
        block.call(evt) if block
      end
    end

    def self.capture_rack_exception(exc, rack_env, configuration=nil, &block)
      configuration ||= Raven.configuration
      capture_exception(exc, configuration) do |evt|
        evt.interface :http do |int|
          int.from_rack(rack_env)
        end
        block.call(evt) if block
      end
    end

    def self.capture_message(message, configuration=nil)
      configuration ||= Raven.configuration
      self.new({}, configuration) do |evt|
        evt.message = message
        evt.level = :error
        evt.interface :message do |int|
          int.message = message
        end
      end
    end

    def get_culprit(frames)
        lastframe = frames[-2]
        "#{lastframe.filename} in #{lastframe.function}" if lastframe
    end

    def parse_exception(exception)
      interface(:exception) do |int|
        int.type = exception.class.to_s
        int.value = exception.message
        int.module = exception.class.to_s.split('::')[0...-1].join('::')
      end
    end

    def parse_backtrace_line(line, frame)
      md = BACKTRACE_RE.match(line)
      raise Error.new("Unable to parse backtrace line: #{line.inspect}") unless md
      frame.abs_path = md[1]
      frame.lineno = md[2].to_i
      frame.function = md[3] if md[3]
      frame.filename = strip_load_path_from(frame.abs_path)
      if context_lines = @configuration[:context_lines]
        frame.pre_context, frame.context_line, frame.post_context = \
          get_context(frame.abs_path, frame.lineno, context_lines)
      end
      frame
    end

    # For cross-language compat
    class << self
      alias :captionException :capture_exception
      alias :captureMessage :capture_message
    end

    private

    # Because linecache can go to hell
    def self._source_lines(path, from, to)
    end

    def get_context(path, line, context)
      lines = (2 * context + 1).times.map do |i|
        Raven::LineCache::getline(path, line - context + i)
      end
      [lines[0..(context-1)], lines[context], lines[(context+1)..-1]]
    end

    def strip_load_path_from(path)
      prefix = $:.select {|s| path.start_with?(s)}.sort_by {|s| s.length}.last
      prefix ? path[prefix.chomp(File::SEPARATOR).length+1..-1] : path
    end
  end
end
