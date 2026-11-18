# frozen_string_literal: true

require "ruby_llm"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/agents/version"
require "sentry/agents/ruby_llm/instrumenter"

module Sentry
  module Agents
    extend Sentry::Integrable

    register_integration name: "agents", version: Sentry::Agents::VERSION

    module RubyLLM
      def self.install(ruby_llm_config = ::RubyLLM.config)
        config = ruby_llm_config.respond_to?(:config) ? ruby_llm_config.config : ruby_llm_config
        Instrumenter.install(config)
      end
    end
  end
end

Sentry::Configuration.after(:configured) { Sentry::Agents::RubyLLM.install }
