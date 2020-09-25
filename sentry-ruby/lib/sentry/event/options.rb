# typed: true

module Sentry
  class Event
    class Options < T::Struct
      extend T::Sig

      prop :message, String, default: ''
      prop :user, T::Hash[T.any(Symbol, String), T.untyped], default: {}
      prop :extra, T::Hash[T.any(Symbol, String), T.untyped], default: {}
      prop :tags, T::Hash[T.any(Symbol, String), T.untyped], default: {}
      prop :backtrace, T::Array[String], default: []
      prop :fingerprint, T::Array[String], default: []
      prop :level, T.any(Symbol, String), default: :error
      prop :checksum, T.nilable(String)
      prop :server_name, T.nilable(String)
      prop :release, T.nilable(String)
      prop :environment, T.nilable(String)
    end
  end
end

