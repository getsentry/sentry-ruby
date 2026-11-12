# frozen_string_literal: true

require "ruby_llm"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/agents/version"

module Sentry
  module Agents
    extend Sentry::Integrable

    register_integration name: "agents", version: Sentry::Agents::VERSION
  end
end
