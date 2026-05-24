require 'sentry-ruby'
require 'concurrent-ruby'

module Sentry
  module ConcurrentRuby
    SENTRY_THREAD_KEY = :sentry_hub
    SENTRY_SPAN_KEY = :sentry_span

    def self.install
      patch_futures
      patch_promises
    end


    def self.patch_futures
      ::Concurrent::Promises.singleton_class.class_eval do
        alias_method :original_future, :future

        def future(*args, &block)
          current_hub = Sentry.get_current_hub
          current_span = Sentry.get_current_scope.get_span
          original_future(*args) do    
            #set the hub and span
            Thread.current.thread_variable_set(Sentry::ConcurrentRuby::SENTRY_THREAD_KEY, current_hub)
            Thread.current.thread_variable_set(Sentry::ConcurrentRuby::SENTRY_SPAN_KEY, current_span)
            Sentry.with_child_span(op: "api.request", description: "Concurrent::Future") do |child_span|
              Sentry.get_current_scope.set_span(child_span)
              block.call
            end
          end
        end
      end
    end


    def self.patch_promises
      ::Concurrent::Promises::Future.class_eval do
        alias_method :original_on_resolution, :on_resolution

        def on_resolution(&block)
          current_hub = Thread.current.thread_variable_get(Sentry::ConcurrentRuby::SENTRY_THREAD_KEY) || Sentry.get_current_hub
          current_span = Sentry.get_current_scope.get_span
          original_on_resolution do |*args|
            Thread.current.thread_variable_set(Sentry::ConcurrentRuby::SENTRY_THREAD_KEY, current_hub)
            Thread.current.thread_variable_set(Sentry::ConcurrentRuby::SENTRY_SPAN_KEY, current_span)
            Sentry.with_child_span(op: "api.request", description: "Concurrent::Promise") do |child_span|
              Sentry.get_current_scope.set_span(child_span)
              block.call(*args)
            end
          end
        end
      end
    end
  end
end

# Install after Sentry loaded
Sentry::ConcurrentRuby.install if defined?(Sentry)
