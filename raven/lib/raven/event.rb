require 'rubygems'
require 'socket'
require 'uuidtools'

require 'raven/error'

module Raven

  class Event

    LOG_LEVELS = {
      "debug" => 10,
      "info" => 20,
      "warn" => 30,
      "warning" => 30,
      "error" => 40,
    }

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

    def self.capture_exception(exc)
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
      end
    end

    # For cross-language compat
    class << self
      alias :captionException :capture_exception
    end

  end

end
