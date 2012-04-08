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
      raise Error.new('A message is required for all events') unless @message && !@message.empty?

      @timestamp = options[:timestamp] || Time.now.utc
      @timestamp = @timestamp.strftime('%Y-%m-%dT%H:%M:%S') if @timestamp.is_a?(Time)
      raise Error.new('A timestamp is required for all events') unless @timestamp

      @level = options[:level]
      @level = LOG_LEVELS[@level.downcase] if @level.is_a?(String)
      raise Error.new('A level is required for all events') unless @level

      @logger = options[:logger] || 'root'
      @culprit = options[:culprit]
      @server_name = options[:server_name] || Socket.gethostbyname(Socket.gethostname).first
      @modules = options[:modules] || Gem::Specification.each.inject({}){|memo, spec| memo[spec.name] = spec.version; memo}
      @extra = options[:extra]

      block.call(self) if block
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
      data
    end

    def self.from_exception(exc)
    end

  end

end
