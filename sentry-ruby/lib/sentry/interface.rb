module Sentry
  class Interface
    def self.inherited(klass)
      name = klass.name.split("::").last.downcase.gsub("interface", "")
      registered[name.to_sym] = klass
      super
    end

    def self.registered
      @@registered ||= {} # rubocop:disable Style/ClassVars
    end

    def to_hash
      Hash[instance_variables.map { |name| [name[1..-1].to_sym, instance_variable_get(name)] }]
    end
  end
end

require "sentry/interfaces/exception"
require "sentry/interfaces/request"
require "sentry/interfaces/single_exception"
require "sentry/interfaces/stacktrace"
require "sentry/interfaces/threads"
