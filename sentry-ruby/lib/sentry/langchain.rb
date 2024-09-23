# frozen_string_literal: true

require "sentry/ai/langchain"

module Sentry
  module Langchain
    def self.setup
      if defined?(::Langchain)
        Sentry::AI::Langchain.patch_langchain_llms
      end
    end
  end
end

Sentry::Langchain.setup