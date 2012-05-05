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

    def initialize(options={}, &block)
      @id = options[:id] || UUIDTools::UUID.random_create.hexdigest

      @message = options[:message]

      @timestamp = options[:timestamp] || Time.now.utc

      @level = options[:level] || :error

      @logger = options[:logger] || 'root'
      @culprit = options[:culprit]
      @server_name = options[:server_name] || Socket.gethostbyname(Socket.gethostname).first
      @modules = options[:modules] || Gem::Specification.each.inject({}){|memo, spec| memo[spec.name] = spec.version; memo}
      @extra = options[:extra]

      @interfaces = {}

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
      self.new do |evt|
        evt.message = exc.message
        evt.level = :error
        evt.interface :exception do |int|
          int.type = exc.class.to_s
          int.value = exc.message
          class_parts = exc.class.to_s.split('::')
          class_parts.pop
          int.module = class_parts.join('::')
        end
        evt.interface :stack_trace do |int|
          int.frames = exc.backtrace.map do |trace_line|
            md = BACKTRACE_RE.match(trace_line)
            raise Error.new("Unable to parse backtrace line: #{trace_line.inspect}") unless md
            int.frame do |frame|
              frame.abs_path = md[1]
              frame.lineno = md[2].to_i
              frame.function = md[3] if md[3]
              lib_path = $:.select{|s| frame.abs_path.start_with?(s)}.sort_by{|s| s.length}.last
              if lib_path
                frame.filename = frame.abs_path[lib_path.chomp(File::SEPARATOR).length+1..frame.abs_path.length]
              else
                frame.filename = frame.abs_path
              end
              if configuration[:context_lines]
                frame.context_line = Raven::LineCache::getline(frame.abs_path, frame.lineno)
                frame.pre_context = (frame.lineno-configuration[:context_lines]..frame.lineno-1).map{|i| Raven::LineCache.getline(frame.abs_path, i)}.select{|line| line}
                frame.post_context = (frame.lineno+1..frame.lineno+configuration[:context_lines]).map{|i| Raven::LineCache.getline(frame.abs_path, i)}.select{|line| line}
              end
            end
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

    # For cross-language compat
    class << self
      alias :captionException :capture_exception
    end

    private

    # Because linecache can go to hell
    def self._source_lines(path, from, to)
    end

  end

end
